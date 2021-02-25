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

#ifndef RADIATION_SOLVER_H
#define RADIATION_SOLVER_H

#include "Array.h"
#include "Gas_concs.h"
#include "Gas_optics_rrtmgp.h"
#include "Cloud_optics.h"
#include "Fluxes.h"

template<typename TF>
class Radiation_solver_longwave
{
    public:
        Radiation_solver_longwave(
                const Gas_concs<TF>& gas_concs,
                const std::string& file_name_gas,
                const std::string& file_name_cloud);

        Radiation_solver_longwave(
                const Gas_concs_gpu<TF>& gas_concs,
                const std::string& file_name_gas,
                const std::string& file_name_cloud);

        void init_work_arrays(
                const int n_col,
                const int n_lev,
                const int n_lay,
                const bool switch_cloud_optics);

        void solve(
                const bool switch_fluxes,
                const bool switch_cloud_optics,
                const bool switch_output_optical,
                const bool switch_output_bnd_fluxes,
                const Gas_concs<TF>& gas_concs,
                const Array<TF,2>& p_lay, const Array<TF,2>& p_lev,
                const Array<TF,2>& t_lay, const Array<TF,2>& t_lev,
                const Array<TF,2>& col_dry,
                const Array<TF,1>& t_sfc, const Array<TF,2>& emis_sfc,
                const Array<TF,2>& lwp, const Array<TF,2>& iwp,
                const Array<TF,2>& rel, const Array<TF,2>& rei,
                Array<TF,3>& tau, Array<TF,3>& lay_source,
                Array<TF,3>& lev_source_inc, Array<TF,3>& lev_source_dec, Array<TF,2>& sfc_source,
                Array<TF,2>& lw_flux_up, Array<TF,2>& lw_flux_dn, Array<TF,2>& lw_flux_net,
                Array<TF,3>& lw_bnd_flux_up, Array<TF,3>& lw_bnd_flux_dn, Array<TF,3>& lw_bnd_flux_net);
        
        int get_n_gpt() const { return this->kdist->get_ngpt(); };
        int get_n_bnd() const { return this->kdist->get_nband(); };

        Array<int,2> get_band_lims_gpoint() const
        { return this->kdist->get_band_lims_gpoint(); }

        Array<TF,2> get_band_lims_wavenumber() const
        { return this->kdist->get_band_lims_wavenumber(); }

        #ifdef __CUDACC__
        void init_work_arrays_gpu(
                const int n_col,
                const int n_lev,
                const int n_lay,
                const bool switch_cloud_optics);

        void solve_gpu(
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
                Array_gpu<TF,3>& lw_bnd_flux_up, Array_gpu<TF,3>& lw_bnd_flux_dn, Array_gpu<TF,3>& lw_bnd_flux_net);

        int get_n_gpt_gpu() const { return this->kdist_gpu->get_ngpt(); };
        int get_n_bnd_gpu() const { return this->kdist_gpu->get_nband(); };
        
        Array<int,2> get_band_lims_gpoint_gpu() const
        { return this->kdist_gpu->get_band_lims_gpoint(); }

        Array<TF,2> get_band_lims_wavenumber_gpu() const
        { return this->kdist_gpu->get_band_lims_wavenumber(); }
        #endif

    private:
        std::unique_ptr<Gas_optics_rrtmgp<TF>> kdist;
        std::unique_ptr<Cloud_optics<TF>> cloud_optics;

        #ifdef __CUDACC__
        std::unique_ptr<Gas_optics_rrtmgp_gpu<TF>> kdist_gpu;
        std::unique_ptr<Cloud_optics_gpu<TF>> cloud_optics_gpu;
        #endif
        struct work_arrays
        {
            Array<TF,2> col_dry_subset;
            Array<TF,3> gpt_flux_up;
            Array<TF,3> gpt_flux_dn;
            Array<TF,2> p_lev_subset;
            Array<TF,2> p_lay_subset;
            Array<TF,2> t_lev_subset;
            Array<TF,2> t_lay_subset;
            Array<TF,1> t_sfc_subset;
            Array<TF,2> emis_sfc_subset;
            Array<TF,2> lwp_lay_subset;
            Array<TF,2> iwp_lay_subset;
            Array<TF,2> rel_lay_subset;
            Array<TF,2> rei_lay_subset;
            std::unique_ptr<Fluxes_broadband<TF>> fluxes_subset;
            std::unique_ptr<Fluxes_broadband<TF>> bnd_fluxes_subset;
        };
            
        work_arrays work_blocks;
        work_arrays work_residual;
        std::tuple<int, int, bool> work_array_config;

        #ifdef __CUDACC__
        struct work_arrays_gpu
        {
            Array_gpu<TF,2> col_dry_subset;
            Array_gpu<TF,3> gpt_flux_up;
            Array_gpu<TF,3> gpt_flux_dn;
            Array_gpu<TF,2> p_lev_subset;
            Array_gpu<TF,2> p_lay_subset;
            Array_gpu<TF,2> t_lev_subset;
            Array_gpu<TF,2> t_lay_subset;
            Array_gpu<TF,1> t_sfc_subset;
            Array_gpu<TF,2> emis_sfc_subset;
            Array_gpu<TF,2> lwp_lay_subset;
            Array_gpu<TF,2> iwp_lay_subset;
            Array_gpu<TF,2> rel_lay_subset;
            Array_gpu<TF,2> rei_lay_subset;
            std::unique_ptr<Fluxes_broadband_gpu<TF>> fluxes_subset;
            std::unique_ptr<Fluxes_broadband_gpu<TF>> bnd_fluxes_subset;
        };
        work_arrays_gpu work_blocks_gpu;
        work_arrays_gpu work_residual_gpu;
        std::tuple<int, int, bool> work_array_config_gpu;
        #endif
};

template<typename TF>
class Radiation_solver_shortwave
{
    public:
        Radiation_solver_shortwave(
                const Gas_concs<TF>& gas_concs,
                const std::string& file_name_gas,
                const std::string& file_name_cloud);
        Radiation_solver_shortwave(
                const Gas_concs_gpu<TF>& gas_concs,
                const std::string& file_name_gas,
                const std::string& file_name_cloud);

        void solve(
                const bool switch_fluxes,
                const bool switch_cloud_optics,
                const bool switch_output_optical,
                const bool switch_output_bnd_fluxes,
                const Gas_concs<TF>& gas_concs,
                const Array<TF,2>& p_lay, const Array<TF,2>& p_lev,
                const Array<TF,2>& t_lay, const Array<TF,2>& t_lev,
                const Array<TF,2>& col_dry,
                const Array<TF,2>& sfc_alb_dir, const Array<TF,2>& sfc_alb_dif,
                const Array<TF,1>& tsi_scaling, const Array<TF,1>& mu0,
                const Array<TF,2>& lwp, const Array<TF,2>& iwp,
                const Array<TF,2>& rel, const Array<TF,2>& rei,
                Array<TF,3>& tau, Array<TF,3>& ssa, Array<TF,3>& g,
                Array<TF,2>& toa_src,
                Array<TF,2>& sw_flux_up, Array<TF,2>& sw_flux_dn,
                Array<TF,2>& sw_flux_dn_dir, Array<TF,2>& sw_flux_net,
                Array<TF,3>& sw_bnd_flux_up, Array<TF,3>& sw_bnd_flux_dn,
                Array<TF,3>& sw_bnd_flux_dn_dir, Array<TF,3>& sw_bnd_flux_net) const;

        int get_n_gpt() const { return this->kdist->get_ngpt(); };
        int get_n_bnd() const { return this->kdist->get_nband(); };

        TF get_tsi() const { return this->kdist->get_tsi(); };

        Array<int,2> get_band_lims_gpoint() const
        { return this->kdist->get_band_lims_gpoint(); }

        Array<TF,2> get_band_lims_wavenumber() const
        { return this->kdist->get_band_lims_wavenumber(); }

        #ifdef __CUDACC__
        void solve_gpu(
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
                Array_gpu<TF,3>& sw_bnd_flux_dn_dir, Array_gpu<TF,3>& sw_bnd_flux_net) const;

        int get_n_gpt_gpu() const { return this->kdist_gpu->get_ngpt(); };
        int get_n_bnd_gpu() const { return this->kdist_gpu->get_nband(); };

        TF get_tsi_gpu() const { return this->kdist_gpu->get_tsi(); };
        
        Array<int,2> get_band_lims_gpoint_gpu() const
        { return this->kdist_gpu->get_band_lims_gpoint(); }

        Array<TF,2> get_band_lims_wavenumber_gpu() const
        { return this->kdist_gpu->get_band_lims_wavenumber(); }
        #endif

    private:
        std::unique_ptr<Gas_optics<TF>> kdist;
        std::unique_ptr<Cloud_optics<TF>> cloud_optics;

        #ifdef __CUDACC__
        std::unique_ptr<Gas_optics_gpu<TF>> kdist_gpu;
        std::unique_ptr<Cloud_optics_gpu<TF>> cloud_optics_gpu;
        #endif
};
#endif
