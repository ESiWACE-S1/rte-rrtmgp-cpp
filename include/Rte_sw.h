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

#ifndef RTE_SW_H
#define RTE_SW_H

#include <memory>
#include <vector>
#include "define_bool.h"

// Forward declarations.
template<typename> class Pool_base;
template<typename> class Pool_client;
template<typename> class Pool_client_group;
template<typename, int> class Array;
template<typename, int> class Array_gpu;
template<typename> class Optical_props_arry;
template<typename> class Optical_props_arry_gpu;
template<typename> class Fluxes_broadband;

template<typename TF>
struct rte_sw_work_arrays: public Pool_client_group<std::vector<TF>>
{
    Array<TF,2> sfc_alb_dir_gpt;
    Array<TF,2> sfc_alb_dif_gpt;

    rte_sw_work_arrays(
            const int ncols,
            const int ngpt,
            Pool_base<std::vector<TF>>* pool=nullptr);
};

template<typename TF>
class Rte_sw
{
    public:
        static void rte_sw(
                const std::unique_ptr<Optical_props_arry<TF>>& optical_props,
                const BOOL_TYPE top_at_1,
                const Array<TF,1>& mu0,
                const Array<TF,2>& inc_flux_dir,
                const Array<TF,2>& sfc_alb_dir,
                const Array<TF,2>& sfc_alb_dif,
                const Array<TF,2>& inc_flux_dif,
                Array<TF,3>& gpt_flux_up,
                Array<TF,3>& gpt_flux_dn,
                Array<TF,3>& gpt_flux_dir,
                rte_sw_work_arrays<TF>* work = nullptr);

        static void expand_and_transpose(
                const std::unique_ptr<Optical_props_arry<TF>>& ops,
                const Array<TF,2>& arr_in,
                Array<TF,2>& arr_out);
};

#ifdef USECUDA
template<typename TF>
struct rte_sw_work_arrays_gpu: public Pool_client_group<TF*>
{
    Array_gpu<TF,2> sfc_alb_dir_gpt;
    Array_gpu<TF,2> sfc_alb_dif_gpt;

    rte_sw_work_arrays_gpu(
            const int ncols,
            const int ngpt,
            Pool_base<TF*>* pool=nullptr);
};

template<typename TF>
class Rte_sw_gpu
{
    public:
        static void rte_sw(
                const std::unique_ptr<Optical_props_arry_gpu<TF>>& optical_props,
                const BOOL_TYPE top_at_1,
                const Array_gpu<TF,1>& mu0,
                const Array_gpu<TF,2>& inc_flux_dir,
                const Array_gpu<TF,2>& sfc_alb_dir,
                const Array_gpu<TF,2>& sfc_alb_dif,
                const Array_gpu<TF,2>& inc_flux_dif,
                Array_gpu<TF,3>& gpt_flux_up,
                Array_gpu<TF,3>& gpt_flux_dn,
                Array_gpu<TF,3>& gpt_flux_dir,
                rte_sw_work_arrays_gpu<TF>* = nullptr);

        static void expand_and_transpose(
                const std::unique_ptr<Optical_props_arry_gpu<TF>>& ops,
                const Array_gpu<TF,2>& arr_in,
                Array_gpu<TF,2>& arr_out);
};

#endif
#endif
