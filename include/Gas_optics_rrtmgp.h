/*
 * This file is part of a C++ interface to the Radiative Transfer for Energetics (RTE)
 * and Rapid Radiative Transfer Model for GCM applications Parallel (RRTMGP).
 *
 * The original code is found at https://github.com/earth-system-radiation/rte-rrtmgp.
 *
 * Contacts: Robert Pincus and Eli Mlawer
 * email: rrtmgp@aer.com
 *
 * Copyright 2015-2020,  Atmospheric and Environmental Research and
 * Regents of the University of Colorado.  All right reserved.
 *
 * This C++ interface can be downloaded from https://github.com/earth-system-radiation/rte-rrtmgp-cpp
 *
 * Contact: Chiel van Heerwaarden
 * email: chiel.vanheerwaarden@wur.nl
 *
 * Copyright 2020, Wageningen University & Research.
 *
 * Use and duplication is permitted under the terms of the
 * BSD 3-clause license, see http://opensource.org/licenses/BSD-3-Clause
 *
 */

#ifndef GAS_OPTICS_RRTMGP_H
#define GAS_OPTICS_RRTMGP_H

#include <string>

#include "Array.h"
#include "Gas_optics.h"
#include "define_bool.h"
#ifdef __CUDACC__
#include "tools_gpu.h"
#endif

// Forward declarations.
// template<typename TF> class Gas_optics;
template<typename TF> class Optical_props;
template<typename TF> class Optical_props_arry;
template<typename TF> class Optical_props_gpu;
template<typename TF> class Optical_props_arry_gpu;
template<typename TF> class Gas_concs;
template<typename TF> class Gas_concs_gpu;
template<typename TF> class Source_func_lw;
template<typename TF> class Source_func_lw_gpu;


template<typename TF>
struct gas_taus_work_arrays
{
    Array<TF,3> tau;
    Array<TF,3> tau_rayleigh;
    Array<TF,3> vmr;
    Array<TF,3> col_gas;
    Array<TF,4> col_mix;
    Array<TF,5> fminor;

    void resize(
        const int ncols,
        const int nlays,
        const int ngpts,
        const int ngas,
        const int nflavs);
};

template<typename TF>
struct gas_source_work_arrays
{
    Array<TF,3> lay_source_t;
    Array<TF,3> lev_source_inc_t;
    Array<TF,3> lev_source_dec_t;
    Array<TF,2> sfc_source_t;
    Array<TF,2> sfc_source_jac;

    void resize(
        const int ncols,
        const int nlays,
        const int ngpts);
};

template<typename TF>
struct gas_optics_work_arrays
{
        Array<int,2> jtemp;
        Array<int,2> jpress;
        Array<BOOL_TYPE,2> tropo;
        Array<TF,6> fmajor;
        Array<int,4> jeta;
        
        std::unique_ptr<gas_taus_work_arrays<TF>> tau_work_arrays;
        std::unique_ptr<gas_source_work_arrays<TF>> source_work_arrays;

        void resize(
                const int ncols,
                const int nlays,
                const int nflavs);
};

template<typename TF>
class Gas_optics_rrtmgp : public Gas_optics<TF>
{
    public:

        // Constructor for longwave variant.
        Gas_optics_rrtmgp(
                const Gas_concs<TF>& available_gases,
                const Array<std::string,1>& gas_names,
                const Array<int,3>& key_species,
                const Array<int,2>& band2gpt,
                const Array<TF,2>& band_lims_wavenum,
                const Array<TF,1>& press_ref,
                const TF press_ref_trop,
                const Array<TF,1>& temp_ref,
                const TF temp_ref_p,
                const TF temp_ref_t,
                const Array<TF,3>& vmr_ref,
                const Array<TF,4>& kmajor,
                const Array<TF,3>& kminor_lower,
                const Array<TF,3>& kminor_upper,
                const Array<std::string,1>& gas_minor,
                const Array<std::string,1>& identifier_minor,
                const Array<std::string,1>& minor_gases_lower,
                const Array<std::string,1>& minor_gases_upper,
                const Array<int,2>& minor_limits_gpt_lower,
                const Array<int,2>& minor_limits_gpt_upper,
                const Array<BOOL_TYPE,1>& minor_scales_with_density_lower,
                const Array<BOOL_TYPE,1>& minor_scales_with_density_upper,
                const Array<std::string,1>& scaling_gas_lower,
                const Array<std::string,1>& scaling_gas_upper,
                const Array<BOOL_TYPE,1>& scale_by_complement_lower,
                const Array<BOOL_TYPE,1>& scale_by_complement_upper,
                const Array<int,1>& kminor_start_lower,
                const Array<int,1>& kminor_start_upper,
                const Array<TF,2>& totplnk,
                const Array<TF,4>& planck_frac,
                const Array<TF,3>& rayl_lower,
                const Array<TF,3>& rayl_upper);

        // Constructor for longwave variant.
        Gas_optics_rrtmgp(
                const Gas_concs<TF>& available_gases,
                const Array<std::string,1>& gas_names,
                const Array<int,3>& key_species,
                const Array<int,2>& band2gpt,
                const Array<TF,2>& band_lims_wavenum,
                const Array<TF,1>& press_ref,
                const TF press_ref_trop,
                const Array<TF,1>& temp_ref,
                const TF temp_ref_p,
                const TF temp_ref_t,
                const Array<TF,3>& vmr_ref,
                const Array<TF,4>& kmajor,
                const Array<TF,3>& kminor_lower,
                const Array<TF,3>& kminor_upper,
                const Array<std::string,1>& gas_minor,
                const Array<std::string,1>& identifier_minor,
                const Array<std::string,1>& minor_gases_lower,
                const Array<std::string,1>& minor_gases_upper,
                const Array<int,2>& minor_limits_gpt_lower,
                const Array<int,2>& minor_limits_gpt_upper,
                const Array<BOOL_TYPE,1>& minor_scales_with_density_lower,
                const Array<BOOL_TYPE,1>& minor_scales_with_density_upper,
                const Array<std::string,1>& scaling_gas_lower,
                const Array<std::string,1>& scaling_gas_upper,
                const Array<BOOL_TYPE,1>& scale_by_complement_lower,
                const Array<BOOL_TYPE,1>& scale_by_complement_upper,
                const Array<int,1>& kminor_start_lower,
                const Array<int,1>& kminor_start_upper,
                const Array<TF,1>& solar_src_quiet,
                const Array<TF,1>& solar_src_facular,
                const Array<TF,1>& solar_src_sunspot,
                const TF tsi_default,
                const TF mg_default,
                const TF sb_default,
                const Array<TF,3>& rayl_lower,
                const Array<TF,3>& rayl_upper);

        static void get_col_dry(
                Array<TF,2>& col_dry,
                const Array<TF,2>& vmr_h2o,
                const Array<TF,2>& plev);

        bool source_is_internal() const { return (totplnk.size() > 0) && (planck_frac.size() > 0); }
        bool source_is_external() const { return (solar_source.size() > 0); }

        TF get_press_ref_min() const { return press_ref_min; }
        TF get_press_ref_max() const { return press_ref_max; }

        TF get_temp_min() const { return temp_ref_min; }
        TF get_temp_max() const { return temp_ref_max; }

        int get_nflav() const { return flavor.dim(2); }
        int get_neta() const { return kmajor.dim(2); }
        int get_npres() const { return kmajor.dim(3)-1; }
        int get_ntemp() const { return kmajor.dim(4); }
        int get_nPlanckTemp() const { return totplnk.dim(1); }
        int get_ngas() const { return this->gas_names.dim(1); }

        TF get_tsi() const;

        // Longwave variant.
        void gas_optics(
                const Array<TF,2>& play,
                const Array<TF,2>& plev,
                const Array<TF,2>& tlay,
                const Array<TF,1>& tsfc,
                const Gas_concs<TF>& gas_desc,
                std::unique_ptr<Optical_props_arry<TF>>& optical_props,
                Source_func_lw<TF>& sources,
                const Array<TF,2>& col_dry,
                const Array<TF,2>& tlev,
                gas_optics_work_arrays<TF>* work_arrays=nullptr) const;

        // Shortwave variant.
        void gas_optics(
                const Array<TF,2>& play,
                const Array<TF,2>& plev,
                const Array<TF,2>& tlay,
                const Gas_concs<TF>& gas_desc,
                std::unique_ptr<Optical_props_arry<TF>>& optical_props,
                Array<TF,2>& toa_src,
                const Array<TF,2>& col_dry,
                gas_optics_work_arrays<TF>* work_arrays=nullptr) const;

        std::unique_ptr<gas_optics_work_arrays<TF>> create_work_arrays(
                const int ncols, 
                const int nlays,
                const int ngpts) const;

    private:
        Array<TF,2> totplnk;
        Array<TF,4> planck_frac;
        TF totplnk_delta;
        TF temp_ref_min, temp_ref_max;
        TF press_ref_min, press_ref_max;
        TF press_ref_trop_log;

        TF press_ref_log_delta;
        TF temp_ref_delta;

        Array<TF,1> press_ref, press_ref_log, temp_ref;

        Array<std::string,1> gas_names;

        Array<TF,3> vmr_ref;

        Array<int,2> flavor;
        Array<int,2> gpoint_flavor;

        Array<TF,4> kmajor;

        Array<TF,3> kminor_lower;
        Array<TF,3> kminor_upper;

        Array<int,2> minor_limits_gpt_lower;
        Array<int,2> minor_limits_gpt_upper;

        Array<BOOL_TYPE,1> minor_scales_with_density_lower;
        Array<BOOL_TYPE,1> minor_scales_with_density_upper;

        Array<BOOL_TYPE,1> scale_by_complement_lower;
        Array<BOOL_TYPE,1> scale_by_complement_upper;

        Array<int,1> kminor_start_lower;
        Array<int,1> kminor_start_upper;

        Array<int,1> idx_minor_lower;
        Array<int,1> idx_minor_upper;

        Array<int,1> idx_minor_scaling_lower;
        Array<int,1> idx_minor_scaling_upper;

        Array<int,1> is_key;

        Array<TF,1> solar_source_quiet;
        Array<TF,1> solar_source_facular;
        Array<TF,1> solar_source_sunspot;
        Array<TF,1> solar_source;
        Array_gpu<TF,1> solar_source_g;

        Array<TF,4> krayl;
        Array_gpu<TF,4> krayl_test;

        void init_abs_coeffs(
                const Gas_concs<TF>& available_gases,
                const Array<std::string,1>& gas_names,
                const Array<int,3>& key_species,
                const Array<int,2>& band2gpt,
                const Array<TF,2>& band_lims_wavenum,
                const Array<TF,1>& press_ref,
                const Array<TF,1>& temp_ref,
                const TF press_ref_trop,
                const TF temp_ref_p,
                const TF temp_ref_t,
                const Array<TF,3>& vmr_ref,
                const Array<TF,4>& kmajor,
                const Array<TF,3>& kminor_lower,
                const Array<TF,3>& kminor_upper,
                const Array<std::string,1>& gas_minor,
                const Array<std::string,1>& identifier_minor,
                const Array<std::string,1>& minor_gases_lower,
                const Array<std::string,1>& minor_gases_upper,
                const Array<int,2>& minor_limits_gpt_lower,
                const Array<int,2>& minor_limits_gpt_upper,
                const Array<BOOL_TYPE,1>& minor_scales_with_density_lower,
                const Array<BOOL_TYPE,1>& minor_scales_with_density_upper,
                const Array<std::string,1>& scaling_gas_lower,
                const Array<std::string,1>& scaling_gas_upper,
                const Array<BOOL_TYPE,1>& scale_by_complement_lower,
                const Array<BOOL_TYPE,1>& scale_by_complement_upper,
                const Array<int,1>& kminor_start_lower,
                const Array<int,1>& kminor_start_upper,
                const Array<TF,3>& rayl_lower,
                const Array<TF,3>& rayl_upper);

        void set_solar_variability(
                const TF md_index, const TF sb_index);

        void compute_gas_taus(
                const int ncol, const int nlay, const int ngpt, const int nband,
                const Array<TF,2>& play,
                const Array<TF,2>& plev,
                const Array<TF,2>& tlay,
                const Gas_concs<TF>& gas_desc,
                std::unique_ptr<Optical_props_arry<TF>>& optical_props,
                Array<int,2>& jtemp, Array<int,2>& jpress,
                Array<int,4>& jeta,
                Array<BOOL_TYPE,2>& tropo,
                Array<TF,6>& fmajor,
                const Array<TF,2>& col_dry,
                gas_taus_work_arrays<TF>* work_arrays=nullptr) const;

        void combine_and_reorder(
                const Array<TF,3>& tau,
                const Array<TF,3>& tau_rayleigh,
                const bool has_rayleigh,
                std::unique_ptr<Optical_props_arry<TF>>& optical_props) const;

        void source(
                const int ncol, const int nlay, const int nband, const int ngpt,
                const Array<TF,2>& play, const Array<TF,2>& plev,
                const Array<TF,2>& tlay, const Array<TF,1>& tsfc,
                const Array<int,2>& jtemp, const Array<int,2>& jpress,
                const Array<int,4>& jeta, const Array<BOOL_TYPE,2>& tropo,
                const Array<TF,6>& fmajor,
                Source_func_lw<TF>& sources,
                const Array<TF,2>& tlev,
                gas_source_work_arrays<TF>* work_arrays=nullptr) const;

};

#ifdef USECUDA
template<typename TF>
struct gas_taus_work_arrays_gpu
{
    Array_gpu<TF,3> tau;
    Array_gpu<TF,3> tau_major;
    Array_gpu<TF,3> tau_minor;
    Array_gpu<TF,3> tau_rayleigh;
    Array_gpu<TF,3> k_rayleigh;
    Array_gpu<TF,3> vmr;
    Array_gpu<TF,3> col_gas;
    Array_gpu<TF,4> col_mix;
    Array_gpu<TF,5> fminor;

    void resize(
        const int ncols,
        const int nlays,
        const int ngpts,
        const int ngas,
        const int nflavs);
};

template<typename TF>
struct gas_source_work_arrays_gpu
{
    Array_gpu<TF,3> lay_source_t;
    Array_gpu<TF,3> lev_source_inc_t;
    Array_gpu<TF,3> lev_source_dec_t;
    Array_gpu<TF,2> sfc_source_t;
    Array_gpu<TF,2> sfc_source_jac;
    Array_gpu<TF,3> p_frac;
    Array_gpu<TF,1> ones;

    void resize(
        const int ncols,
        const int nlays,
        const int ngpts);

};

template<typename TF>
struct gas_optics_work_arrays_gpu
{
        int n_cols;
        int n_lays;
        Array_gpu<int,2> jtemp;
        Array_gpu<int,2> jpress;
        Array_gpu<BOOL_TYPE,2> tropo;
        Array_gpu<TF,6> fmajor;
        Array_gpu<int,4> jeta;
        std::unique_ptr<gas_taus_work_arrays_gpu<TF>> tau_work_arrays;
        std::unique_ptr<gas_source_work_arrays_gpu<TF>> source_work_arrays;

        void resize(
                const int ncols,
                const int nlays,
                const int ngpts);
};

template<typename TF>
class Gas_optics_rrtmgp_gpu : public Gas_optics_gpu<TF>
{
    public:
        // Constructor for longwave variant.
        Gas_optics_rrtmgp_gpu(
                const Gas_concs_gpu<TF>& available_gases,
                const Array<std::string,1>& gas_names,
                const Array<int,3>& key_species,
                const Array<int,2>& band2gpt,
                const Array<TF,2>& band_lims_wavenum,
                const Array<TF,1>& press_ref,
                const TF press_ref_trop,
                const Array<TF,1>& temp_ref,
                const TF temp_ref_p,
                const TF temp_ref_t,
                const Array<TF,3>& vmr_ref,
                const Array<TF,4>& kmajor,
                const Array<TF,3>& kminor_lower,
                const Array<TF,3>& kminor_upper,
                const Array<std::string,1>& gas_minor,
                const Array<std::string,1>& identifier_minor,
                const Array<std::string,1>& minor_gases_lower,
                const Array<std::string,1>& minor_gases_upper,
                const Array<int,2>& minor_limits_gpt_lower,
                const Array<int,2>& minor_limits_gpt_upper,
                const Array<BOOL_TYPE,1>& minor_scales_with_density_lower,
                const Array<BOOL_TYPE,1>& minor_scales_with_density_upper,
                const Array<std::string,1>& scaling_gas_lower,
                const Array<std::string,1>& scaling_gas_upper,
                const Array<BOOL_TYPE,1>& scale_by_complement_lower,
                const Array<BOOL_TYPE,1>& scale_by_complement_upper,
                const Array<int,1>& kminor_start_lower,
                const Array<int,1>& kminor_start_upper,
                const Array<TF,2>& totplnk,
                const Array<TF,4>& planck_frac,
                const Array<TF,3>& rayl_lower,
                const Array<TF,3>& rayl_upper);

        // Constructor for shortwave variant.
        Gas_optics_rrtmgp_gpu(
                const Gas_concs_gpu<TF>& available_gases,
                const Array<std::string,1>& gas_names,
                const Array<int,3>& key_species,
                const Array<int,2>& band2gpt,
                const Array<TF,2>& band_lims_wavenum,
                const Array<TF,1>& press_ref,
                const TF press_ref_trop,
                const Array<TF,1>& temp_ref,
                const TF temp_ref_p,
                const TF temp_ref_t,
                const Array<TF,3>& vmr_ref,
                const Array<TF,4>& kmajor,
                const Array<TF,3>& kminor_lower,
                const Array<TF,3>& kminor_upper,
                const Array<std::string,1>& gas_minor,
                const Array<std::string,1>& identifier_minor,
                const Array<std::string,1>& minor_gases_lower,
                const Array<std::string,1>& minor_gases_upper,
                const Array<int,2>& minor_limits_gpt_lower,
                const Array<int,2>& minor_limits_gpt_upper,
                const Array<BOOL_TYPE,1>& minor_scales_with_density_lower,
                const Array<BOOL_TYPE,1>& minor_scales_with_density_upper,
                const Array<std::string,1>& scaling_gas_lower,
                const Array<std::string,1>& scaling_gas_upper,
                const Array<BOOL_TYPE,1>& scale_by_complement_lower,
                const Array<BOOL_TYPE,1>& scale_by_complement_upper,
                const Array<int,1>& kminor_start_lower,
                const Array<int,1>& kminor_start_upper,
                const Array<TF,1>& solar_src_quiet,
                const Array<TF,1>& solar_src_facular,
                const Array<TF,1>& solar_src_sunspot,
                const TF tsi_default,
                const TF mg_default,
                const TF sb_default,
                const Array<TF,3>& rayl_lower,
                const Array<TF,3>& rayl_upper);

        static void get_col_dry(
                Array_gpu<TF,2>& col_dry,
                const Array_gpu<TF,2>& vmr_h2o,
                const Array_gpu<TF,2>& plev);

        bool source_is_internal() const { return (totplnk.size() > 0) && (planck_frac.size() > 0); }
        bool source_is_external() const { return (solar_source.size() > 0); }

        TF get_press_ref_min() const { return press_ref_min; }
        TF get_press_ref_max() const { return press_ref_max; }

        TF get_temp_min() const { return temp_ref_min; }
        TF get_temp_max() const { return temp_ref_max; }

        int get_nflav() const { return flavor.dim(2); }
        int get_neta() const { return kmajor.dim(2); }
        int get_npres() const { return kmajor.dim(3)-1; }
        int get_ntemp() const { return kmajor.dim(4); }
        int get_nPlanckTemp() const { return totplnk.dim(1); }

        TF get_tsi() const;

        // Longwave variant.
        void gas_optics(
                const Array_gpu<TF,2>& play,
                const Array_gpu<TF,2>& plev,
                const Array_gpu<TF,2>& tlay,
                const Array_gpu<TF,1>& tsfc,
                const Gas_concs_gpu<TF>& gas_desc,
                std::unique_ptr<Optical_props_arry_gpu<TF>>& optical_props,
                Source_func_lw_gpu<TF>& sources,
                const Array_gpu<TF,2>& col_dry,
                const Array_gpu<TF,2>& tlev,
                gas_optics_work_arrays_gpu<TF>* work_arrays=nullptr) const;

        //shortwave variant
           void gas_optics(
                const Array_gpu<TF,2>& play,
                const Array_gpu<TF,2>& plev,
                const Array_gpu<TF,2>& tlay,
                const Gas_concs_gpu<TF>& gas_desc,
                std::unique_ptr<Optical_props_arry_gpu<TF>>& optical_props,
                Array_gpu<TF,2>& toa_src,
                const Array_gpu<TF,2>& col_dry) const;

        std::unique_ptr<gas_optics_work_arrays_gpu<TF>> create_work_arrays(
                const int ncols, 
                const int nlays,
                const int ngpts) const;

    private:
        Array<TF,2> totplnk;
        Array<TF,4> planck_frac;
        TF totplnk_delta;
        TF temp_ref_min, temp_ref_max;
        TF press_ref_min, press_ref_max;
        TF press_ref_trop_log;

        TF press_ref_log_delta;
        TF temp_ref_delta;

        Array<TF,1> press_ref, press_ref_log, temp_ref;

        Array<std::string,1> gas_names;

        Array<TF,3> vmr_ref;

        Array<int,2> flavor;
        Array<int,2> gpoint_flavor;

        Array<TF,4> kmajor;

        Array<TF,3> kminor_lower;
        Array<TF,3> kminor_upper;

        Array<int,2> minor_limits_gpt_lower;
        Array<int,2> minor_limits_gpt_upper;

        Array<BOOL_TYPE,1> minor_scales_with_density_lower;
        Array<BOOL_TYPE,1> minor_scales_with_density_upper;

        Array<BOOL_TYPE,1> scale_by_complement_lower;
        Array<BOOL_TYPE,1> scale_by_complement_upper;

        Array<int,1> kminor_start_lower;
        Array<int,1> kminor_start_upper;

        Array<int,1> idx_minor_lower;
        Array<int,1> idx_minor_upper;

        Array<int,1> idx_minor_scaling_lower;
        Array<int,1> idx_minor_scaling_upper;

        Array<int,1> is_key;

        Array<TF,1> solar_source_quiet;
        Array<TF,1> solar_source_facular;
        Array<TF,1> solar_source_sunspot;
        Array<TF,1> solar_source;

        Array<TF,4> krayl;

        #ifdef USECUDA
        Array_gpu<TF,1> solar_source_g;
        Array_gpu<TF,2> totplnk_gpu;
        Array_gpu<TF,4> planck_frac_gpu;
        Array_gpu<TF,1> press_ref_gpu, press_ref_log_gpu, temp_ref_gpu;
        Array_gpu<TF,3> vmr_ref_gpu;
        Array_gpu<int,2> flavor_gpu;
        Array_gpu<int,2> gpoint_flavor_gpu;
        Array_gpu<TF,4> kmajor_gpu;
        Array_gpu<TF,3> kminor_lower_gpu;
        Array_gpu<TF,3> kminor_upper_gpu;
        Array_gpu<int,2> minor_limits_gpt_lower_gpu;
        Array_gpu<int,2> minor_limits_gpt_upper_gpu;
        Array_gpu<BOOL_TYPE,1> minor_scales_with_density_lower_gpu;
        Array_gpu<BOOL_TYPE,1> minor_scales_with_density_upper_gpu;
        Array_gpu<BOOL_TYPE,1> scale_by_complement_lower_gpu;
        Array_gpu<BOOL_TYPE,1> scale_by_complement_upper_gpu;
        Array_gpu<int,1> kminor_start_lower_gpu;
        Array_gpu<int,1> kminor_start_upper_gpu;
        Array_gpu<int,1> idx_minor_lower_gpu;
        Array_gpu<int,1> idx_minor_upper_gpu;
        Array_gpu<int,1> idx_minor_scaling_lower_gpu;
        Array_gpu<int,1> idx_minor_scaling_upper_gpu;
//        Array_gpu<int,1> is_key_gpu;
        Array_gpu<TF,1> solar_source_gpu;
        Array_gpu<TF,4> krayl_gpu;
        #endif



        int get_ngas() const { return this->gas_names.dim(1); }

        void init_abs_coeffs(
                const Gas_concs_gpu<TF>& available_gases,
                const Array<std::string,1>& gas_names,
                const Array<int,3>& key_species,
                const Array<int,2>& band2gpt,
                const Array<TF,2>& band_lims_wavenum,
                const Array<TF,1>& press_ref,
                const Array<TF,1>& temp_ref,
                const TF press_ref_trop,
                const TF temp_ref_p,
                const TF temp_ref_t,
                const Array<TF,3>& vmr_ref,
                const Array<TF,4>& kmajor,
                const Array<TF,3>& kminor_lower,
                const Array<TF,3>& kminor_upper,
                const Array<std::string,1>& gas_minor,
                const Array<std::string,1>& identifier_minor,
                const Array<std::string,1>& minor_gases_lower,
                const Array<std::string,1>& minor_gases_upper,
                const Array<int,2>& minor_limits_gpt_lower,
                const Array<int,2>& minor_limits_gpt_upper,
                const Array<BOOL_TYPE,1>& minor_scales_with_density_lower,
                const Array<BOOL_TYPE,1>& minor_scales_with_density_upper,
                const Array<std::string,1>& scaling_gas_lower,
                const Array<std::string,1>& scaling_gas_upper,
                const Array<BOOL_TYPE,1>& scale_by_complement_lower,
                const Array<BOOL_TYPE,1>& scale_by_complement_upper,
                const Array<int,1>& kminor_start_lower,
                const Array<int,1>& kminor_start_upper,
                const Array<TF,3>& rayl_lower,
                const Array<TF,3>& rayl_upper);

        void set_solar_variability(
                const TF md_index, const TF sb_index);

        void compute_gas_taus(
                const int ncol, const int nlay, const int ngpt, const int nband,
                const Array_gpu<TF,2>& play,
                const Array_gpu<TF,2>& plev,
                const Array_gpu<TF,2>& tlay,
                const Gas_concs_gpu<TF>& gas_desc,
                std::unique_ptr<Optical_props_arry_gpu<TF>>& optical_props,
                Array_gpu<int,2>& jtemp, Array_gpu<int,2>& jpress,
                Array_gpu<int,4>& jeta,
                Array_gpu<BOOL_TYPE,2>& tropo,
                Array_gpu<TF,6>& fmajor,
                const Array_gpu<TF,2>& col_dry,
                gas_taus_work_arrays_gpu<TF>* work_arrays=nullptr) const;

        void combine_and_reorder(
                const Array_gpu<TF,3>& tau,
                const Array_gpu<TF,3>& tau_rayleigh,
                const bool has_rayleigh,
                std::unique_ptr<Optical_props_arry_gpu<TF>>& optical_props) const;

        void source(
                const int ncol, const int nlay, const int nband, const int ngpt,
                const Array_gpu<TF,2>& play, const Array_gpu<TF,2>& plev,
                const Array_gpu<TF,2>& tlay, const Array_gpu<TF,1>& tsfc,
                const Array_gpu<int,2>& jtemp, const Array_gpu<int,2>& jpress,
                const Array_gpu<int,4>& jeta, const Array_gpu<BOOL_TYPE,2>& tropo,
                const Array_gpu<TF,6>& fmajor,
                Source_func_lw_gpu<TF>& sources,
                const Array_gpu<TF,2>& tlev,
                gas_source_work_arrays_gpu<TF>* work=nullptr) const;

};


#endif
#endif
