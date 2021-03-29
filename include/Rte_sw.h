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
#include "Types.h"

// Forward declarations.
template<typename, int> class Array;
template<typename, int> class Array_gpu;
class Optical_props_arry;
class Optical_props_arry_gpu;


class Rte_sw
{
    public:
        static void rte_sw(
                const std::unique_ptr<Optical_props_arry>& optical_props,
                const Bool top_at_1,
                const Array<Real,1>& mu0,
                const Array<Real,2>& inc_flux_dir,
                const Array<Real,2>& sfc_alb_dir,
                const Array<Real,2>& sfc_alb_dif,
                const Array<Real,2>& inc_flux_dif,
                Array<Real,3>& gpt_flux_up,
                Array<Real,3>& gpt_flux_dn,
                Array<Real,3>& gpt_flux_dir);

        static void expand_and_transpose(
                const std::unique_ptr<Optical_props_arry>& ops,
                const Array<Real,2> arr_in,
                Array<Real,2>& arr_out);
};


#ifdef USECUDA
class Rte_sw_gpu
{
    public:
        static void rte_sw(
                const std::unique_ptr<Optical_props_arry_gpu>& optical_props,
                const Bool top_at_1,
                const Array_gpu<Real,1>& mu0,
                const Array_gpu<Real,2>& inc_flux_dir,
                const Array_gpu<Real,2>& sfc_alb_dir,
                const Array_gpu<Real,2>& sfc_alb_dif,
                const Array_gpu<Real,2>& inc_flux_dif,
                Array_gpu<Real,3>& gpt_flux_up,
                Array_gpu<Real,3>& gpt_flux_dn,
                Array_gpu<Real,3>& gpt_flux_dir);

        static void expand_and_transpose(
                const std::unique_ptr<Optical_props_arry_gpu>& ops,
                const Array_gpu<Real,2> arr_in,
                Array_gpu<Real,2>& arr_out);
};
#endif

#endif
