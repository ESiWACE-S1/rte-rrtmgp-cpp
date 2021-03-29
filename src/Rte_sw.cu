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

#include "Rte_sw.h"
#include "Array.h"
#include "Optical_props.h"
#include "Fluxes.h"
#include "rrtmgp_kernels.h"
// CUDA TEST
#include "rte_kernel_launcher_cuda.h"
// END CUDA TEST

namespace
{
    __global__
    void expand_and_transpose_kernel(
        const int ncol, const int nbnd, const int* __restrict__ limits,
        Real* __restrict__ arr_out, const Real* __restrict__ arr_in)
    {
        const int icol = blockIdx.x*blockDim.x + threadIdx.x;
        const int ibnd = blockIdx.y*blockDim.y + threadIdx.y;

        if ( ( icol < ncol) && (ibnd < nbnd) )
        {
            const int gpt_start = limits[2*ibnd] - 1;
            const int gpt_end = limits[2*ibnd+1];

            for (int igpt=gpt_start; igpt<gpt_end; ++igpt)
            {
                const int idx_in = ibnd + icol*nbnd;
                const int idx_out = icol + igpt*ncol;

                arr_out[idx_out] = arr_in[idx_in];
            }
        }
    }
}

//namespace rrtmgp_kernel_launcher
//{
//    template<typename Real>
//    void apply_BC(
//            int ncol, int nlay, int ngpt,
//            Bool top_at_1, Array<Real,3>& gpt_flux_dn)
//    {
//        rrtmgp_kernels::apply_BC_0(
//                &ncol, &nlay, &ngpt,
//                &top_at_1, gpt_flux_dn.ptr());
//    }
//
//    template<typename Real>
//    void apply_BC(
//            int ncol, int nlay, int ngpt, Bool top_at_1,
//            const Array<Real,2>& inc_flux, Array<Real,3>& gpt_flux_dn)
//    {
//        rrtmgp_kernels::apply_BC_gpt(
//                &ncol, &nlay, &ngpt, &top_at_1,
//                const_cast<Real*>(inc_flux.ptr()), gpt_flux_dn.ptr());
//    }
//
//    template<typename Real>
//    void apply_BC(
//            int ncol, int nlay, int ngpt, Bool top_at_1,
//            const Array<Real,2>& inc_flux,
//            const Array<Real,1>& factor,
//            Array<Real,3>& gpt_flux)
//    {
//        rrtmgp_kernels::apply_BC_factor(
//                &ncol, &nlay, &ngpt,
//                &top_at_1,
//                const_cast<Real*>(inc_flux.ptr()),
//                const_cast<Real*>(factor.ptr()),
//                gpt_flux.ptr());
//    }
//
//    template<typename Real>
//    void sw_solver_2stream(
//            int ncol, int nlay, int ngpt, Bool top_at_1,
//            const Array<Real,3>& tau,
//            const Array<Real,3>& ssa,
//            const Array<Real,3>& g,
//            const Array<Real,1>& mu0,
//            const Array<Real,2>& sfc_alb_dir_gpt, const Array<Real,2>& sfc_alb_dif_gpt,
//            Array<Real,3>& gpt_flux_up, Array<Real,3>& gpt_flux_dn, Array<Real,3>& gpt_flux_dir)
//    {
//        rrtmgp_kernels::sw_solver_2stream(
//                &ncol, &nlay, &ngpt, &top_at_1,
//                const_cast<Real*>(tau.ptr()),
//                const_cast<Real*>(ssa.ptr()),
//                const_cast<Real*>(g  .ptr()),
//                const_cast<Real*>(mu0.ptr()),
//                const_cast<Real*>(sfc_alb_dir_gpt.ptr()),
//                const_cast<Real*>(sfc_alb_dif_gpt.ptr()),
//                gpt_flux_up.ptr(), gpt_flux_dn.ptr(), gpt_flux_dir.ptr());
//    }

void Rte_sw_gpu::rte_sw(
        const std::unique_ptr<Optical_props_arry_gpu>& optical_props,
        const Bool top_at_1,
        const Array_gpu<Real,1>& mu0,
        const Array_gpu<Real,2>& inc_flux_dir,
        const Array_gpu<Real,2>& sfc_alb_dir,
        const Array_gpu<Real,2>& sfc_alb_dif,
        const Array_gpu<Real,2>& inc_flux_dif,
        Array_gpu<Real,3>& gpt_flux_up,
        Array_gpu<Real,3>& gpt_flux_dn,
        Array_gpu<Real,3>& gpt_flux_dir)
{
    const int ncol = optical_props->get_ncol();
    const int nlay = optical_props->get_nlay();
    const int ngpt = optical_props->get_ngpt();

    Array_gpu<Real,2> sfc_alb_dir_gpt({ncol, ngpt});
    Array_gpu<Real,2> sfc_alb_dif_gpt({ncol, ngpt});

    expand_and_transpose(optical_props, sfc_alb_dir, sfc_alb_dir_gpt);
    expand_and_transpose(optical_props, sfc_alb_dif, sfc_alb_dif_gpt);

    // Upper boundary condition. At this stage, flux_dn contains the diffuse radiation only.
    rte_kernel_launcher_cuda::apply_BC(ncol, nlay, ngpt, top_at_1, inc_flux_dir, mu0, gpt_flux_dir);
    if (inc_flux_dif.size() == 0)
        rte_kernel_launcher_cuda::apply_BC(ncol, nlay, ngpt, top_at_1, gpt_flux_dn);
    else
        rte_kernel_launcher_cuda::apply_BC(ncol, nlay, ngpt, top_at_1, inc_flux_dif, gpt_flux_dn);

    // Run the radiative transfer solver
    // CvH: only two-stream solutions, I skipped the sw_solver_noscat.
    rte_kernel_launcher_cuda::sw_solver_2stream(
            ncol, nlay, ngpt, top_at_1,
            optical_props->get_tau(),
            optical_props->get_ssa(),
            optical_props->get_g  (),
            mu0,
            sfc_alb_dir_gpt, sfc_alb_dif_gpt,
            gpt_flux_up, gpt_flux_dn, gpt_flux_dir);

    // CvH: The original fortran code had a call to the reduce here.
    // fluxes->reduce(gpt_flux_up, gpt_flux_dn, gpt_flux_dir, optical_props, top_at_1);
}

void Rte_sw_gpu::expand_and_transpose(
        const std::unique_ptr<Optical_props_arry_gpu>& ops,
        const Array_gpu<Real,2> arr_in,
        Array_gpu<Real,2>& arr_out)
{
    const int ncol = arr_in.dim(2);
    const int nbnd = ops->get_nband();
    const int block_col = 16;
    const int block_bnd = 14;

    const int grid_col = ncol/block_col + (ncol%block_col > 0);
    const int grid_bnd = nbnd/block_bnd + (nbnd%block_bnd > 0);

    dim3 grid_gpu(grid_col, grid_bnd);
    dim3 block_gpu(block_col, block_bnd);

    Array_gpu<int,2> limits = ops->get_band_lims_gpoint_gpu();

    // Array_gpu<int,2> limits(limitsc);
    expand_and_transpose_kernel<<<grid_gpu, block_gpu>>>(
        ncol, nbnd, limits.ptr(), arr_out.ptr(), arr_in.ptr());
}
