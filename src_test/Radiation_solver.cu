/*
 * This file is imported from MicroHH (https://github.com/earth-system-radiation/earth-system-radiation)
 * and is adapted for the testing of the C++ interface to the
 * RTE+RRTMGP radiation code.
 *
 * MicroHH is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * MicroHH is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with MicroHH.  If not, see <http://www.gnu.org/licenses/>.
 */

#include <boost/algorithm/string.hpp>
#include <cmath>
#include <numeric>

#include "Radiation_solver.h"
#include "Status.h"
#include "Netcdf_interface.h"

#include "Array.h"
#include "Gas_concs.h"
#include "Gas_optics_rrtmgp.h"
#include "Optical_props.h"
#include "Source_functions.h"
#include "Fluxes.h"
#include "Rte_lw.h"
#include "Rte_sw.h"
#include "subset_kernel_launcher_cuda.h"

#include <cuda_profiler_api.h>
namespace
{
    template<typename TF>__global__
    void scaling_to_subset_kernel(
            const int ncol, const int ngpt, TF* __restrict__ toa_src, const TF* __restrict__ tsi_scaling)
    {
        const int icol = blockIdx.x*blockDim.x + threadIdx.x;
        const int igpt = blockIdx.y*blockDim.y + threadIdx.y;
        if ( ( icol < ncol) && (igpt < ngpt) )
        {
            const int idx = icol + igpt*ncol;
            toa_src[idx] *= tsi_scaling[icol];
        }
    }

    template<typename TF>
    void scaling_to_subset(
            const int ncol, const int ngpt, Array_gpu<TF,2>& toa_src, const Array_gpu<TF,1>& tsi_scaling)
    {
        const int block_col = 16;
        const int block_gpt = 16;
        const int grid_col  = ncol/block_col + (ncol%block_col > 0);
        const int grid_gpt  = ngpt/block_gpt + (ngpt%block_gpt > 0);
        dim3 grid_gpu(grid_col, grid_gpt);
        dim3 block_gpu(block_col, block_gpt);
        scaling_to_subset_kernel<<<grid_gpu, block_gpu>>>(
            ncol, ngpt, toa_src.ptr(), tsi_scaling.ptr());
    }


    std::vector<std::string> get_variable_string(
            const std::string& var_name,
            std::vector<int> i_count,
            Netcdf_handle& input_nc,
            const int string_len,
            bool trim=true)
    {
        // Multiply all elements in i_count.
        int total_count = std::accumulate(i_count.begin(), i_count.end(), 1, std::multiplies<>());

        // Add the string length as the rightmost dimension.
        i_count.push_back(string_len);

        // Read the entire char array;
        std::vector<char> var_char;
        var_char = input_nc.get_variable<char>(var_name, i_count);

        std::vector<std::string> var;

        for (int n=0; n<total_count; ++n)
        {
            std::string s(var_char.begin()+n*string_len, var_char.begin()+(n+1)*string_len);
            if (trim)
                boost::trim(s);
            var.push_back(s);
        }

        return var;
    }

    template<typename TF>
    Gas_optics_rrtmgp_gpu<TF> load_and_init_gas_optics(
            const Gas_concs_gpu<TF>& gas_concs,
            const std::string& coef_file)
    {
        // READ THE COEFFICIENTS FOR THE OPTICAL SOLVER.
        Netcdf_file coef_nc(coef_file, Netcdf_mode::Read);

        // Read k-distribution information.
        int n_temps = coef_nc.get_dimension_size("temperature");
        int n_press = coef_nc.get_dimension_size("pressure");
        int n_absorbers = coef_nc.get_dimension_size("absorber");

        // CvH: I hardcode the value to 32 now, because coef files
        // CvH: changed dimension name inconsistently.
        // int n_char = coef_nc.get_dimension_size("string_len");
        constexpr int n_char = 32;

        int n_minorabsorbers = coef_nc.get_dimension_size("minor_absorber");
        int n_extabsorbers = coef_nc.get_dimension_size("absorber_ext");
        int n_mixingfracs = coef_nc.get_dimension_size("mixing_fraction");
        int n_layers = coef_nc.get_dimension_size("atmos_layer");
        int n_bnds = coef_nc.get_dimension_size("bnd");
        int n_gpts = coef_nc.get_dimension_size("gpt");
        int n_pairs = coef_nc.get_dimension_size("pair");
        int n_minor_absorber_intervals_lower = coef_nc.get_dimension_size("minor_absorber_intervals_lower");
        int n_minor_absorber_intervals_upper = coef_nc.get_dimension_size("minor_absorber_intervals_upper");
        int n_contributors_lower = coef_nc.get_dimension_size("contributors_lower");
        int n_contributors_upper = coef_nc.get_dimension_size("contributors_upper");

        // Read gas names.
        Array<std::string,1> gas_names(
                get_variable_string("gas_names", {n_absorbers}, coef_nc, n_char, true), {n_absorbers});

        Array<int,3> key_species(
                coef_nc.get_variable<int>("key_species", {n_bnds, n_layers, 2}),
                {2, n_layers, n_bnds});
        Array<TF,2> band_lims(coef_nc.get_variable<TF>("bnd_limits_wavenumber", {n_bnds, 2}), {2, n_bnds});
        Array<int,2> band2gpt(coef_nc.get_variable<int>("bnd_limits_gpt", {n_bnds, 2}), {2, n_bnds});
        Array<TF,1> press_ref(coef_nc.get_variable<TF>("press_ref", {n_press}), {n_press});
        Array<TF,1> temp_ref(coef_nc.get_variable<TF>("temp_ref", {n_temps}), {n_temps});

        TF temp_ref_p = coef_nc.get_variable<TF>("absorption_coefficient_ref_P");
        TF temp_ref_t = coef_nc.get_variable<TF>("absorption_coefficient_ref_T");
        TF press_ref_trop = coef_nc.get_variable<TF>("press_ref_trop");

        Array<TF,3> kminor_lower(
                coef_nc.get_variable<TF>("kminor_lower", {n_temps, n_mixingfracs, n_contributors_lower}),
                {n_contributors_lower, n_mixingfracs, n_temps});
        Array<TF,3> kminor_upper(
                coef_nc.get_variable<TF>("kminor_upper", {n_temps, n_mixingfracs, n_contributors_upper}),
                {n_contributors_upper, n_mixingfracs, n_temps});

        Array<std::string,1> gas_minor(get_variable_string("gas_minor", {n_minorabsorbers}, coef_nc, n_char),
                                       {n_minorabsorbers});

        Array<std::string,1> identifier_minor(
                get_variable_string("identifier_minor", {n_minorabsorbers}, coef_nc, n_char), {n_minorabsorbers});

        Array<std::string,1> minor_gases_lower(
                get_variable_string("minor_gases_lower", {n_minor_absorber_intervals_lower}, coef_nc, n_char),
                {n_minor_absorber_intervals_lower});
        Array<std::string,1> minor_gases_upper(
                get_variable_string("minor_gases_upper", {n_minor_absorber_intervals_upper}, coef_nc, n_char),
                {n_minor_absorber_intervals_upper});

        Array<int,2> minor_limits_gpt_lower(
                coef_nc.get_variable<int>("minor_limits_gpt_lower", {n_minor_absorber_intervals_lower, n_pairs}),
                {n_pairs, n_minor_absorber_intervals_lower});
        Array<int,2> minor_limits_gpt_upper(
                coef_nc.get_variable<int>("minor_limits_gpt_upper", {n_minor_absorber_intervals_upper, n_pairs}),
                {n_pairs, n_minor_absorber_intervals_upper});

        Array<BOOL_TYPE,1> minor_scales_with_density_lower(
                coef_nc.get_variable<BOOL_TYPE>("minor_scales_with_density_lower", {n_minor_absorber_intervals_lower}),
                {n_minor_absorber_intervals_lower});
        Array<BOOL_TYPE,1> minor_scales_with_density_upper(
                coef_nc.get_variable<BOOL_TYPE>("minor_scales_with_density_upper", {n_minor_absorber_intervals_upper}),
                {n_minor_absorber_intervals_upper});

        Array<BOOL_TYPE,1> scale_by_complement_lower(
                coef_nc.get_variable<BOOL_TYPE>("scale_by_complement_lower", {n_minor_absorber_intervals_lower}),
                {n_minor_absorber_intervals_lower});
        Array<BOOL_TYPE,1> scale_by_complement_upper(
                coef_nc.get_variable<BOOL_TYPE>("scale_by_complement_upper", {n_minor_absorber_intervals_upper}),
                {n_minor_absorber_intervals_upper});

        Array<std::string,1> scaling_gas_lower(
                get_variable_string("scaling_gas_lower", {n_minor_absorber_intervals_lower}, coef_nc, n_char),
                {n_minor_absorber_intervals_lower});
        Array<std::string,1> scaling_gas_upper(
                get_variable_string("scaling_gas_upper", {n_minor_absorber_intervals_upper}, coef_nc, n_char),
                {n_minor_absorber_intervals_upper});

        Array<int,1> kminor_start_lower(
                coef_nc.get_variable<int>("kminor_start_lower", {n_minor_absorber_intervals_lower}),
                {n_minor_absorber_intervals_lower});
        Array<int,1> kminor_start_upper(
                coef_nc.get_variable<int>("kminor_start_upper", {n_minor_absorber_intervals_upper}),
                {n_minor_absorber_intervals_upper});

        Array<TF,3> vmr_ref(
                coef_nc.get_variable<TF>("vmr_ref", {n_temps, n_extabsorbers, n_layers}),
                {n_layers, n_extabsorbers, n_temps});

        Array<TF,4> kmajor(
                coef_nc.get_variable<TF>("kmajor", {n_temps, n_press+1, n_mixingfracs, n_gpts}),
                {n_gpts, n_mixingfracs, n_press+1, n_temps});

        // Keep the size at zero, if it does not exist.
        Array<TF,3> rayl_lower;
        Array<TF,3> rayl_upper;

        if (coef_nc.variable_exists("rayl_lower"))
        {
            rayl_lower.set_dims({n_gpts, n_mixingfracs, n_temps});
            rayl_upper.set_dims({n_gpts, n_mixingfracs, n_temps});
            rayl_lower = coef_nc.get_variable<TF>("rayl_lower", {n_temps, n_mixingfracs, n_gpts});
            rayl_upper = coef_nc.get_variable<TF>("rayl_upper", {n_temps, n_mixingfracs, n_gpts});
        }

        // Is it really LW if so read these variables as well.
        if (coef_nc.variable_exists("totplnk"))
        {
            int n_internal_sourcetemps = coef_nc.get_dimension_size("temperature_Planck");

            Array<TF,2> totplnk(
                    coef_nc.get_variable<TF>( "totplnk", {n_bnds, n_internal_sourcetemps}),
                    {n_internal_sourcetemps, n_bnds});
            Array<TF,4> planck_frac(
                    coef_nc.get_variable<TF>("plank_fraction", {n_temps, n_press+1, n_mixingfracs, n_gpts}),
                    {n_gpts, n_mixingfracs, n_press+1, n_temps});

            // Construct the k-distribution.
            return Gas_optics_rrtmgp_gpu<TF>(
                    gas_concs,
                    gas_names,
                    key_species,
                    band2gpt,
                    band_lims,
                    press_ref,
                    press_ref_trop,
                    temp_ref,
                    temp_ref_p,
                    temp_ref_t,
                    vmr_ref,
                    kmajor,
                    kminor_lower,
                    kminor_upper,
                    gas_minor,
                    identifier_minor,
                    minor_gases_lower,
                    minor_gases_upper,
                    minor_limits_gpt_lower,
                    minor_limits_gpt_upper,
                    minor_scales_with_density_lower,
                    minor_scales_with_density_upper,
                    scaling_gas_lower,
                    scaling_gas_upper,
                    scale_by_complement_lower,
                    scale_by_complement_upper,
                    kminor_start_lower,
                    kminor_start_upper,
                    totplnk,
                    planck_frac,
                    rayl_lower,
                    rayl_upper);
        }
        else
        {
            Array<TF,1> solar_src_quiet(
                    coef_nc.get_variable<TF>("solar_source_quiet", {n_gpts}), {n_gpts});
            Array<TF,1> solar_src_facular(
                    coef_nc.get_variable<TF>("solar_source_facular", {n_gpts}), {n_gpts});
            Array<TF,1> solar_src_sunspot(
                    coef_nc.get_variable<TF>("solar_source_sunspot", {n_gpts}), {n_gpts});

            TF tsi = coef_nc.get_variable<TF>("tsi_default");
            TF mg_index = coef_nc.get_variable<TF>("mg_default");
            TF sb_index = coef_nc.get_variable<TF>("sb_default");

            return Gas_optics_rrtmgp_gpu<TF>(
                    gas_concs,
                    gas_names,
                    key_species,
                    band2gpt,
                    band_lims,
                    press_ref,
                    press_ref_trop,
                    temp_ref,
                    temp_ref_p,
                    temp_ref_t,
                    vmr_ref,
                    kmajor,
                    kminor_lower,
                    kminor_upper,
                    gas_minor,
                    identifier_minor,
                    minor_gases_lower,
                    minor_gases_upper,
                    minor_limits_gpt_lower,
                    minor_limits_gpt_upper,
                    minor_scales_with_density_lower,
                    minor_scales_with_density_upper,
                    scaling_gas_lower,
                    scaling_gas_upper,
                    scale_by_complement_lower,
                    scale_by_complement_upper,
                    kminor_start_lower,
                    kminor_start_upper,
                    solar_src_quiet,
                    solar_src_facular,
                    solar_src_sunspot,
                    tsi,
                    mg_index,
                    sb_index,
                    rayl_lower,
                    rayl_upper);
        }
        // End reading of k-distribution.
    }

    template<typename TF>
    Cloud_optics_gpu<TF> load_and_init_cloud_optics(
            const std::string& coef_file)
    {
        // READ THE COEFFICIENTS FOR THE OPTICAL SOLVER.
        Netcdf_file coef_nc(coef_file, Netcdf_mode::Read);

        // Read look-up table coefficient dimensions
        int n_band     = coef_nc.get_dimension_size("nband");
        int n_rghice   = coef_nc.get_dimension_size("nrghice");
        int n_size_liq = coef_nc.get_dimension_size("nsize_liq");
        int n_size_ice = coef_nc.get_dimension_size("nsize_ice");

        Array<TF,2> band_lims_wvn(coef_nc.get_variable<TF>("bnd_limits_wavenumber", {n_band, 2}), {2, n_band});

        // Read look-up table constants.
        TF radliq_lwr = coef_nc.get_variable<TF>("radliq_lwr");
        TF radliq_upr = coef_nc.get_variable<TF>("radliq_upr");
        TF radliq_fac = coef_nc.get_variable<TF>("radliq_fac");

        TF radice_lwr = coef_nc.get_variable<TF>("radice_lwr");
        TF radice_upr = coef_nc.get_variable<TF>("radice_upr");
        TF radice_fac = coef_nc.get_variable<TF>("radice_fac");

        Array<TF,2> lut_extliq(
                coef_nc.get_variable<TF>("lut_extliq", {n_band, n_size_liq}), {n_size_liq, n_band});
        Array<TF,2> lut_ssaliq(
                coef_nc.get_variable<TF>("lut_ssaliq", {n_band, n_size_liq}), {n_size_liq, n_band});
        Array<TF,2> lut_asyliq(
                coef_nc.get_variable<TF>("lut_asyliq", {n_band, n_size_liq}), {n_size_liq, n_band});

        Array<TF,3> lut_extice(
                coef_nc.get_variable<TF>("lut_extice", {n_rghice, n_band, n_size_ice}), {n_size_ice, n_band, n_rghice});
        Array<TF,3> lut_ssaice(
                coef_nc.get_variable<TF>("lut_ssaice", {n_rghice, n_band, n_size_ice}), {n_size_ice, n_band, n_rghice});
        Array<TF,3> lut_asyice(
                coef_nc.get_variable<TF>("lut_asyice", {n_rghice, n_band, n_size_ice}), {n_size_ice, n_band, n_rghice});

        return Cloud_optics_gpu<TF>(
                band_lims_wvn,
                radliq_lwr, radliq_upr, radliq_fac,
                radice_lwr, radice_upr, radice_fac,
                lut_extliq, lut_ssaliq, lut_asyliq,
                lut_extice, lut_ssaice, lut_asyice);
    }
}

template<typename TF>
Radiation_solver_longwave<TF>::Radiation_solver_longwave(
        const Gas_concs_gpu<TF>& gas_concs,
        const std::string& file_name_gas,
        const std::string& file_name_cloud)
{
    // Construct the gas optics classes for the solver.
    this->kdist_gpu = std::make_unique<Gas_optics_rrtmgp_gpu<TF>>(
            load_and_init_gas_optics<TF>(gas_concs, file_name_gas));

    this->cloud_optics_gpu = std::make_unique<Cloud_optics_gpu<TF>>(
            load_and_init_cloud_optics<TF>(file_name_cloud));
}

template<typename TF>
void Radiation_solver_longwave<TF>::solve_gpu(
        const bool switch_fluxes,
        const bool switch_cloud_optics,
        const bool switch_output_optical,
        const bool switch_output_bnd_fluxes,
        const Gas_concs_gpu<TF>& gas_concs,
        const Array_gpu<TF,2>& p_lay, const Array_gpu<TF,2>& p_lev,
        const Array_gpu<TF,2>& t_lay, const Array_gpu<TF,2>& t_lev,
        const Array_gpu<TF,2>& col_dry,
        const Array_gpu<TF,1>& t_sfc, const Array_gpu<TF,2>& emis_sfc,
        const Array_gpu<TF,2>& lwp, const Array_gpu<TF,2>& iwp,
        const Array_gpu<TF,2>& rel, const Array_gpu<TF,2>& rei,
        Array_gpu<TF,3>& tau, Array_gpu<TF,3>& lay_source,
        Array_gpu<TF,3>& lev_source_inc, Array_gpu<TF,3>& lev_source_dec, Array_gpu<TF,2>& sfc_source,
        Array_gpu<TF,2>& lw_flux_up, Array_gpu<TF,2>& lw_flux_dn, Array_gpu<TF,2>& lw_flux_net,
        Array_gpu<TF,3>& lw_bnd_flux_up, Array_gpu<TF,3>& lw_bnd_flux_dn, Array_gpu<TF,3>& lw_bnd_flux_net) const
{
    const int n_col = p_lay.dim(1);
    const int n_lay = p_lay.dim(2);
    const int n_lev = p_lev.dim(2);
    const int n_gpt = this->kdist_gpu->get_ngpt();
    const int n_bnd = this->kdist_gpu->get_nband();

    const BOOL_TYPE top_at_1 = p_lay({1, 1}) < p_lay({1, n_lay});

    constexpr int n_col_block = 16;

    // Read the sources and create containers for the substeps.
    int n_blocks = n_col / n_col_block;
    int n_col_block_residual = n_col % n_col_block;

    std::unique_ptr<Optical_props_arry_gpu<TF>> optical_props_subset;
    std::unique_ptr<Optical_props_arry_gpu<TF>> optical_props_residual;

    optical_props_subset = std::make_unique<Optical_props_1scl_gpu<TF>>(n_col_block, n_lay, *kdist_gpu);

    std::unique_ptr<Source_func_lw_gpu<TF>> sources_subset;
    std::unique_ptr<Source_func_lw_gpu<TF>> sources_residual;

    sources_subset = std::make_unique<Source_func_lw_gpu<TF>>(n_col_block, n_lay, *kdist_gpu);

    if (n_col_block_residual > 0)
    {
        optical_props_residual = std::make_unique<Optical_props_1scl_gpu<TF>>(n_col_block_residual, n_lay, *kdist_gpu);
        sources_residual = std::make_unique<Source_func_lw_gpu<TF>>(n_col_block_residual, n_lay, *kdist_gpu);
    }

    std::unique_ptr<Optical_props_1scl_gpu<TF>> cloud_optical_props_subset;
    std::unique_ptr<Optical_props_1scl_gpu<TF>> cloud_optical_props_residual;

    if (switch_cloud_optics)
    {
        cloud_optical_props_subset = std::make_unique<Optical_props_1scl_gpu<TF>>(n_col_block, n_lay, *cloud_optics_gpu);
        if (n_col_block_residual > 0)
            cloud_optical_props_residual = std::make_unique<Optical_props_1scl_gpu<TF>>(n_col_block_residual, n_lay, *cloud_optics_gpu);
    }

    // Lambda function for solving optical properties subset.
    auto call_kernels = [&](
            const int col_s_in, const int col_e_in,
            std::unique_ptr<Optical_props_arry_gpu<TF>>& optical_props_subset_in,
            std::unique_ptr<Optical_props_1scl_gpu<TF>>& cloud_optical_props_subset_in,
            Source_func_lw_gpu<TF>& sources_subset_in,
            const Array_gpu<TF,2>& emis_sfc_subset_in,
            Fluxes_broadband_gpu<TF>& fluxes,
            Fluxes_broadband_gpu<TF>& bnd_fluxes)
    {
        const int n_col_in = col_e_in - col_s_in + 1;
        Gas_concs_gpu<TF> gas_concs_subset(gas_concs, col_s_in, n_col_in);

        auto p_lev_subset = p_lev.subset({{ {col_s_in, col_e_in}, {1, n_lev} }});

        Array_gpu<TF,2> col_dry_subset({n_col_in, n_lay});
        if (col_dry.size() == 0)
            Gas_optics_rrtmgp_gpu<TF>::get_col_dry(col_dry_subset, gas_concs_subset.get_vmr("h2o"), p_lev_subset);
        else
            col_dry_subset = col_dry.subset({{ {col_s_in, col_e_in}, {1, n_lay} }});

        kdist_gpu->gas_optics(
                p_lay.subset({{ {col_s_in, col_e_in}, {1, n_lay} }}),
                p_lev_subset,
                t_lay.subset({{ {col_s_in, col_e_in}, {1, n_lay} }}),
                t_sfc.subset({{ {col_s_in, col_e_in} }}),
                gas_concs_subset,
                optical_props_subset_in,
                sources_subset_in,
                col_dry_subset,
                t_lev.subset({{ {col_s_in, col_e_in}, {1, n_lev} }}) );

        if (switch_cloud_optics)
        {
            cloud_optics_gpu->cloud_optics(
                    lwp.subset({{ {col_s_in, col_e_in}, {1, n_lay} }}),
                    iwp.subset({{ {col_s_in, col_e_in}, {1, n_lay} }}),
                    rel.subset({{ {col_s_in, col_e_in}, {1, n_lay} }}),
                    rei.subset({{ {col_s_in, col_e_in}, {1, n_lay} }}),
                    *cloud_optical_props_subset_in);

            // cloud->delta_scale();

            // Add the cloud optical props to the gas optical properties.
            add_to(
                    dynamic_cast<Optical_props_1scl_gpu<double>&>(*optical_props_subset_in),
                    dynamic_cast<Optical_props_1scl_gpu<double>&>(*cloud_optical_props_subset_in));
        }

        // Store the optical properties, if desired.
        if (switch_output_optical)
        {
            subset_kernel_launcher_cuda::get_from_subset(
                    n_col, n_lay, n_gpt, n_col_in, col_s_in, tau, lay_source, lev_source_inc, lev_source_dec,
                    optical_props_subset_in->get_tau(), sources_subset_in.get_lay_source(),
                    sources_subset_in.get_lev_source_inc(), sources_subset_in.get_lev_source_dec());

            subset_kernel_launcher_cuda::get_from_subset(
                    n_col, n_gpt, n_col_in, col_s_in, sfc_source, sources_subset_in.get_sfc_source());
        }

        if (!switch_fluxes)
            return;

        Array_gpu<TF,3> gpt_flux_up({n_col_in, n_lev, n_gpt});
        Array_gpu<TF,3> gpt_flux_dn({n_col_in, n_lev, n_gpt});

        constexpr int n_ang = 1;

        Rte_lw_gpu<TF>::rte_lw(
                optical_props_subset_in,
                top_at_1,
                sources_subset_in,
                emis_sfc_subset_in,
                Array_gpu<TF,2>(), // Add an empty array, no inc_flux.
                gpt_flux_up, gpt_flux_dn,
                n_ang);
        fluxes.reduce(gpt_flux_up, gpt_flux_dn, optical_props_subset_in, top_at_1);

        // Copy the data to the output.
        subset_kernel_launcher_cuda::get_from_subset(
                n_col, n_lev, n_col_in, col_s_in, lw_flux_up, lw_flux_dn, lw_flux_net,
                fluxes.get_flux_up(), fluxes.get_flux_dn(), fluxes.get_flux_net());


        if (switch_output_bnd_fluxes)
        {
            bnd_fluxes.reduce(gpt_flux_up, gpt_flux_dn, optical_props_subset_in, top_at_1);

            subset_kernel_launcher_cuda::get_from_subset(
                    n_col, n_lev, n_bnd, n_col_in, col_s_in, lw_bnd_flux_up, lw_bnd_flux_dn, lw_bnd_flux_net,
                    bnd_fluxes.get_bnd_flux_up(), bnd_fluxes.get_bnd_flux_dn(), bnd_fluxes.get_bnd_flux_net());

        }
    };

    for (int b=1; b<=n_blocks; ++b)
    {
        const int col_s = (b-1) * n_col_block + 1;
        const int col_e =  b    * n_col_block;

        Array_gpu<TF,2> emis_sfc_subset = emis_sfc.subset({{ {1, n_bnd}, {col_s, col_e} }});

        std::unique_ptr<Fluxes_broadband_gpu<TF>> fluxes_subset =
                std::make_unique<Fluxes_broadband_gpu<TF>>(n_col_block, n_lev);
        std::unique_ptr<Fluxes_broadband_gpu<TF>> bnd_fluxes_subset =
                std::make_unique<Fluxes_byband_gpu<TF>>(n_col_block, n_lev, n_bnd);

        call_kernels(
                col_s, col_e,
                optical_props_subset,
                cloud_optical_props_subset,
                *sources_subset,
                emis_sfc_subset,
                *fluxes_subset,
                *bnd_fluxes_subset);
    }

    if (n_col_block_residual > 0)
    {
        const int col_s = n_col - n_col_block_residual + 1;
        const int col_e = n_col;

        Array_gpu<TF,2> emis_sfc_residual = emis_sfc.subset({{ {1, n_bnd}, {col_s, col_e} }});
        std::unique_ptr<Fluxes_broadband_gpu<TF>> fluxes_residual =
                std::make_unique<Fluxes_broadband_gpu<TF>>(n_col_block_residual, n_lev);
        std::unique_ptr<Fluxes_broadband_gpu<TF>> bnd_fluxes_residual =
                std::make_unique<Fluxes_byband_gpu<TF>>(n_col_block_residual, n_lev, n_bnd);

        call_kernels(
                col_s, col_e,
                optical_props_residual,
                cloud_optical_props_residual,
                *sources_residual,
                emis_sfc_residual,
                *fluxes_residual,
                *bnd_fluxes_residual);
    }
}

template<typename TF>
Radiation_solver_shortwave<TF>::Radiation_solver_shortwave(
        const Gas_concs_gpu<TF>& gas_concs,
        const std::string& file_name_gas,
        const std::string& file_name_cloud)
{
    // Construct the gas optics classes for the solver.
    this->kdist_gpu = std::make_unique<Gas_optics_rrtmgp_gpu<TF>>(
            load_and_init_gas_optics<TF>(gas_concs, file_name_gas));

    this->cloud_optics_gpu = std::make_unique<Cloud_optics_gpu<TF>>(
            load_and_init_cloud_optics<TF>(file_name_cloud));
}


template<typename TF>
void Radiation_solver_shortwave<TF>::solve_gpu(
        const bool switch_fluxes,
        const bool switch_cloud_optics,
        const bool switch_output_optical,
        const bool switch_output_bnd_fluxes,
        const Gas_concs_gpu<TF>& gas_concs,
        const Array_gpu<TF,2>& p_lay, const Array_gpu<TF,2>& p_lev,
        const Array_gpu<TF,2>& t_lay, const Array_gpu<TF,2>& t_lev,
        const Array_gpu<TF,2>& col_dry,
        const Array_gpu<TF,2>& sfc_alb_dir, const Array_gpu<TF,2>& sfc_alb_dif,
        const Array_gpu<TF,1>& tsi_scaling, const Array_gpu<TF,1>& mu0,
        const Array_gpu<TF,2>& lwp, const Array_gpu<TF,2>& iwp,
        const Array_gpu<TF,2>& rel, const Array_gpu<TF,2>& rei,
        Array_gpu<TF,3>& tau, Array_gpu<TF,3>& ssa, Array_gpu<TF,3>& g,
        Array_gpu<TF,2>& toa_src,
        Array_gpu<TF,2>& sw_flux_up, Array_gpu<TF,2>& sw_flux_dn,
        Array_gpu<TF,2>& sw_flux_dn_dir, Array_gpu<TF,2>& sw_flux_net,
        Array_gpu<TF,3>& sw_bnd_flux_up, Array_gpu<TF,3>& sw_bnd_flux_dn,
        Array_gpu<TF,3>& sw_bnd_flux_dn_dir, Array_gpu<TF,3>& sw_bnd_flux_net) const
{
    const int n_col = p_lay.dim(1);
    const int n_lay = p_lay.dim(2);
    const int n_lev = p_lev.dim(2);
    const int n_gpt = this->kdist_gpu->get_ngpt();
    const int n_bnd = this->kdist_gpu->get_nband();

    const BOOL_TYPE top_at_1 = p_lay({1, 1}) < p_lay({1, n_lay});

    constexpr int n_col_block = 16;

    // Read the sources and create containers for the substeps.
    int n_blocks = n_col / n_col_block;
    int n_col_block_residual = n_col % n_col_block;

    std::unique_ptr<Optical_props_arry_gpu<TF>> optical_props_subset;
    std::unique_ptr<Optical_props_arry_gpu<TF>> optical_props_residual;

    optical_props_subset = std::make_unique<Optical_props_2str_gpu<TF>>(n_col_block, n_lay, *kdist_gpu);
    if (n_col_block_residual > 0)
        optical_props_residual = std::make_unique<Optical_props_2str_gpu<TF>>(n_col_block_residual, n_lay, *kdist_gpu);

    std::unique_ptr<Optical_props_2str_gpu<TF>> cloud_optical_props_subset;
    std::unique_ptr<Optical_props_2str_gpu<TF>> cloud_optical_props_residual;

    if (switch_cloud_optics)
    {
        cloud_optical_props_subset = std::make_unique<Optical_props_2str_gpu<TF>>(n_col_block, n_lay, *cloud_optics_gpu);
        if (n_col_block_residual > 0)
            cloud_optical_props_residual = std::make_unique<Optical_props_2str_gpu<TF>>(n_col_block_residual, n_lay, *cloud_optics_gpu);
    }

    // Lambda function for solving optical properties subset.
    auto call_kernels = [&, n_col, n_lay, n_lev, n_gpt, n_bnd](
            const int col_s_in, const int col_e_in,
            std::unique_ptr<Optical_props_arry_gpu<TF>>& optical_props_subset_in,
            std::unique_ptr<Optical_props_2str_gpu<TF>>& cloud_optical_props_subset_in,
            Fluxes_broadband_gpu<TF>& fluxes,
            Fluxes_broadband_gpu<TF>& bnd_fluxes)
    {
        const int n_col_in = col_e_in - col_s_in + 1;
        Gas_concs_gpu<TF> gas_concs_subset(gas_concs, col_s_in, n_col_in);

        auto p_lev_subset = p_lev.subset({{ {col_s_in, col_e_in}, {1, n_lev} }});

        Array_gpu<TF,2> col_dry_subset({n_col_in, n_lay});
        if (col_dry.size() == 0)
            Gas_optics_rrtmgp_gpu<TF>::get_col_dry(col_dry_subset, gas_concs_subset.get_vmr("h2o"), p_lev_subset);
        else
            col_dry_subset = col_dry.subset({{ {col_s_in, col_e_in}, {1, n_lay} }});

        Array_gpu<TF,2> toa_src_subset({n_col_in, n_gpt});
        kdist_gpu->gas_optics(
                  p_lay.subset({{ {col_s_in, col_e_in}, {1, n_lay} }}),
                  p_lev_subset,
                  t_lay.subset({{ {col_s_in, col_e_in}, {1, n_lay} }}),
                  gas_concs_subset,
                  optical_props_subset_in,
                  toa_src_subset,
                  col_dry_subset);
        auto tsi_scaling_subset = tsi_scaling.subset({{ {col_s_in, col_e_in} }});
        scaling_to_subset(n_col_in, n_gpt, toa_src_subset, tsi_scaling_subset);
        if (switch_cloud_optics)
        {
            Array<int,2> cld_mask_liq({n_col_in, n_lay});
            Array<int,2> cld_mask_ice({n_col_in, n_lay});

            cloud_optics_gpu->cloud_optics(
                    lwp.subset({{ {col_s_in, col_e_in}, {1, n_lay} }}),
                    iwp.subset({{ {col_s_in, col_e_in}, {1, n_lay} }}),
                    rel.subset({{ {col_s_in, col_e_in}, {1, n_lay} }}),
                    rei.subset({{ {col_s_in, col_e_in}, {1, n_lay} }}),
                    *cloud_optical_props_subset_in);

            cloud_optical_props_subset_in->delta_scale();

            // Add the cloud optical props to the gas optical properties.
            add_to(
                    dynamic_cast<Optical_props_2str_gpu<double>&>(*optical_props_subset_in),
                    dynamic_cast<Optical_props_2str_gpu<double>&>(*cloud_optical_props_subset_in));

        }

        // Store the optical properties, if desired.
        if (switch_output_optical)
        {
            subset_kernel_launcher_cuda::get_from_subset(
                    n_col, n_lay, n_gpt, n_col_in, col_s_in, tau, ssa, g, optical_props_subset_in->get_tau(),
                     optical_props_subset_in->get_ssa(),  optical_props_subset_in->get_g());

            subset_kernel_launcher_cuda::get_from_subset(
                    n_col, n_gpt, n_col_in, col_s_in, toa_src, toa_src_subset);
        }
        if (!switch_fluxes)
            return;

        Array_gpu<TF,3> gpt_flux_up    ({n_col_in, n_lev, n_gpt});
        Array_gpu<TF,3> gpt_flux_dn    ({n_col_in, n_lev, n_gpt});
        Array_gpu<TF,3> gpt_flux_dn_dir({n_col_in, n_lev, n_gpt});
        Rte_sw_gpu<TF>::rte_sw(
                optical_props_subset_in,
                top_at_1,
                mu0.subset({{ {col_s_in, col_e_in} }}),
                toa_src_subset,
                sfc_alb_dir.subset({{ {1, n_bnd}, {col_s_in, col_e_in} }}),
                sfc_alb_dif.subset({{ {1, n_bnd}, {col_s_in, col_e_in} }}),
                Array_gpu<TF,2>(), // Add an empty array, no inc_flux.
                gpt_flux_up,
                gpt_flux_dn,
                gpt_flux_dn_dir);

        fluxes.reduce(gpt_flux_up, gpt_flux_dn, gpt_flux_dn_dir, optical_props_subset_in, top_at_1);

        // Copy the data to the output.
        subset_kernel_launcher_cuda::get_from_subset(
                n_col, n_lev, n_col_in, col_s_in, sw_flux_up, sw_flux_dn, sw_flux_dn_dir, sw_flux_net,
                fluxes.get_flux_up(), fluxes.get_flux_dn(), fluxes.get_flux_dn_dir(), fluxes.get_flux_net());

        if (switch_output_bnd_fluxes)
        {
            bnd_fluxes.reduce(gpt_flux_up, gpt_flux_dn, optical_props_subset_in, top_at_1);

            subset_kernel_launcher_cuda::get_from_subset(
                    n_col, n_lev, n_bnd, n_col_in, col_s_in, sw_bnd_flux_up, sw_bnd_flux_dn, sw_bnd_flux_dn_dir, sw_bnd_flux_net,
                    bnd_fluxes.get_bnd_flux_up(), bnd_fluxes.get_bnd_flux_dn(), bnd_fluxes.get_bnd_flux_dn_dir(), bnd_fluxes.get_bnd_flux_net());
        }
    };


    for (int b=1; b<=n_blocks; ++b)
    {
        const int col_s = (b-1) * n_col_block + 1;
        const int col_e =  b    * n_col_block;

        std::unique_ptr<Fluxes_broadband_gpu<TF>> fluxes_subset =
                std::make_unique<Fluxes_broadband_gpu<TF>>(n_col_block, n_lev);
        std::unique_ptr<Fluxes_broadband_gpu<TF>> bnd_fluxes_subset =
                std::make_unique<Fluxes_byband_gpu<TF>>(n_col_block, n_lev, n_bnd);

        call_kernels(
                col_s, col_e,
                optical_props_subset,
                cloud_optical_props_subset,
                *fluxes_subset,
                *bnd_fluxes_subset);
    }

    if (n_col_block_residual > 0)
    {
        const int col_s = n_col - n_col_block_residual + 1;
        const int col_e = n_col;

        std::unique_ptr<Fluxes_broadband_gpu<TF>> fluxes_residual =
                std::make_unique<Fluxes_broadband_gpu<TF>>(n_col_block_residual, n_lev);
        std::unique_ptr<Fluxes_broadband_gpu<TF>> bnd_fluxes_residual =
                std::make_unique<Fluxes_byband_gpu<TF>>(n_col_block_residual, n_lev, n_bnd);

        call_kernels(
                col_s, col_e,
                optical_props_residual,
                cloud_optical_props_residual,
                *fluxes_residual,
                *bnd_fluxes_residual);
    }
}

#ifdef FLOAT_SINGLE_RRTMGP
template class Radiation_solver_longwave<float>;
template class Radiation_solver_shortwave<float>;
#else
template class Radiation_solver_longwave<double>;
template class Radiation_solver_shortwave<double>;
#endif
