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

#include "Cloud_optics.h"

namespace
{
    template<typename TF>__global__
    void compute_from_table_kernel(
            const int ncol, const int nlay, const int nbnd, const BOOL_TYPE* mask,
            const TF* cwp, const TF* re,
            const int nsteps, const TF step_size, const TF offset,
            const TF* tau_table, const TF* ssa_table, const TF* asy_table,
            TF* tau, TF* taussa, TF* taussag)
    {
        const int ibnd = blockIdx.x*blockDim.x + threadIdx.x;
        const int ilay = blockIdx.y*blockDim.y + threadIdx.y;
        const int icol = blockIdx.z*blockDim.z + threadIdx.z;

        if ( ( icol < ncol) && ( ilay < nlay) && (ibnd < nbnd) )
        {
            const int idx_2d = icol + ilay*ncol;
            const int idx_3d = icol + ilay*ncol + ibnd*nlay*ncol;

            if (mask[idx_2d])
            {
                const int index = min(int((re[idx_2d] - offset) / step_size) + 1, nsteps-1) - 1;
                const int idx_ib = index + ibnd*nsteps;
                const TF fint = (re[idx_2d] - offset) /step_size - (index);
                const TF tau_local = cwp[idx_2d] *
                                     (tau_table[idx_ib] + fint * (tau_table[idx_ib+1] - tau_table[idx_ib]));
                const TF taussa_local = tau_local *
                                     (ssa_table[idx_ib] + fint * (ssa_table[idx_ib+1] - ssa_table[idx_ib]));
                const TF taussag_local = taussa_local *
                                     (asy_table[idx_ib] + fint * (asy_table[idx_ib+1] - asy_table[idx_ib]));

                tau[idx_3d]     = tau_local;
                taussa[idx_3d]  = taussa_local;
                taussag[idx_3d] = taussag_local;
            }
            else
            {
                tau[idx_3d]     = TF(0.);
                taussa[idx_3d]  = TF(0.);
                taussag[idx_3d] = TF(0.);
            }
        }
    }

    template<typename TF>__global__
    void combine_and_store_kernel(const int ncol, const int nlay, const int nbnd, const TF tmin,
                  TF* __restrict__ tau,
                  const TF* __restrict__ ltau, const TF* __restrict__ ltaussa,
                  const TF* __restrict__ itau, const TF* __restrict__ itaussa)
    {
        const int ibnd = blockIdx.x*blockDim.x + threadIdx.x;
        const int ilay = blockIdx.y*blockDim.y + threadIdx.y;
        const int icol = blockIdx.z*blockDim.z + threadIdx.z;

        if ( (icol < ncol) && (ilay < nlay) && (ibnd < nbnd) )
        {
            const int idx = icol + ilay*ncol + ibnd*nlay*ncol;
            const TF tau_t = (ltau[idx] - ltaussa[idx]) + (itau[idx] - itaussa[idx]);

            tau[idx] = tau_t;
        }
    }

    template<typename TF>__global__
    void combine_and_store_kernel(const int ncol, const int nlay, const int nbnd, const TF tmin,
                  TF* __restrict__ tau, TF* __restrict__ ssa, TF* __restrict__ g,
                  const TF* __restrict__ ltau, const TF* __restrict__ ltaussa, const TF* __restrict__ ltaussag,
                  const TF* __restrict__ itau, const TF* __restrict__ itaussa, const TF* __restrict__ itaussag)
    {
        const int ibnd = blockIdx.x*blockDim.x + threadIdx.x;
        const int ilay = blockIdx.y*blockDim.y + threadIdx.y;
        const int icol = blockIdx.z*blockDim.z + threadIdx.z;

        if ( (icol < ncol) && (ilay < nlay) && (ibnd < nbnd) )
        {
            const int idx = icol + ilay*ncol + ibnd*nlay*ncol;
            const TF tau_t = ltau[idx] + itau[idx];
            const TF taussa = ltaussa[idx] + itaussa[idx];
            const TF taussag = ltaussag[idx] + itaussag[idx];

            tau[idx] = tau_t;
            ssa[idx] = taussa / max(tau_t, tmin);
            g[idx]   = taussag/ max(taussa, tmin);
        }
    }

    template<typename TF>__global__
    void set_mask(const int ncol, const int nlay, const TF min_value,
                  BOOL_TYPE* __restrict__ mask, const TF* __restrict__ values)
    {
        const int icol = blockIdx.x*blockDim.x + threadIdx.x;
        const int ilay = blockIdx.y*blockDim.y + threadIdx.y;

        if ( (icol < ncol) && (ilay < nlay) )
        {
            const int idx = icol + ilay*ncol;
            mask[idx] = values[idx] > min_value;
        }
    }
}


template<typename TF>
Cloud_optics_gpu<TF>::Cloud_optics_gpu(
        const Array<TF,2>& band_lims_wvn,
        const TF radliq_lwr, const TF radliq_upr, const TF radliq_fac,
        const TF radice_lwr, const TF radice_upr, const TF radice_fac,
        const Array<TF,2>& lut_extliq, const Array<TF,2>& lut_ssaliq, const Array<TF,2>& lut_asyliq,
        const Array<TF,3>& lut_extice, const Array<TF,3>& lut_ssaice, const Array<TF,3>& lut_asyice) :
    Optical_props_gpu<TF>(band_lims_wvn)
{
    const int nsize_liq = lut_extliq.dim(1);
    const int nsize_ice = lut_extice.dim(1);

    this->liq_nsteps = nsize_liq;
    this->ice_nsteps = nsize_ice;
    this->liq_step_size = (radliq_upr - radliq_lwr) / (nsize_liq - TF(1.));
    this->ice_step_size = (radice_upr - radice_lwr) / (nsize_ice - TF(1.));

    // Load LUT constants.
    this->radliq_lwr = radliq_lwr;
    this->radliq_upr = radliq_upr;
    this->radice_lwr = radice_lwr;
    this->radice_upr = radice_upr;

    // Load LUT coefficients.
    this->lut_extliq = lut_extliq;
    this->lut_ssaliq = lut_ssaliq;
    this->lut_asyliq = lut_asyliq;

    // Choose the intermediately rough ice particle category (icergh = 2).
    this->lut_extice.set_dims({lut_extice.dim(1), lut_extice.dim(2)});
    this->lut_ssaice.set_dims({lut_ssaice.dim(1), lut_ssaice.dim(2)});
    this->lut_asyice.set_dims({lut_asyice.dim(1), lut_asyice.dim(2)});

    constexpr int icergh = 2;
    for (int ibnd=1; ibnd<=lut_extice.dim(2); ++ibnd)
        for (int isize=1; isize<=lut_extice.dim(1); ++isize)
        {
            this->lut_extice({isize, ibnd}) = lut_extice({isize, ibnd, icergh});
            this->lut_ssaice({isize, ibnd}) = lut_ssaice({isize, ibnd, icergh});
            this->lut_asyice({isize, ibnd}) = lut_asyice({isize, ibnd, icergh});
        }

    this->lut_extice_gpu = this->lut_extice;
    this->lut_ssaice_gpu = this->lut_ssaice;
    this->lut_asyice_gpu = this->lut_asyice;
    this->lut_extliq_gpu = this->lut_extliq;
    this->lut_ssaliq_gpu = this->lut_ssaliq;
    this->lut_asyliq_gpu = this->lut_asyliq;
}


// Two-stream variant of cloud optics.
template<typename TF>
void Cloud_optics_gpu<TF>::cloud_optics(
        const Array_gpu<TF,2>& clwp, const Array_gpu<TF,2>& ciwp,
        const Array_gpu<TF,2>& reliq, const Array_gpu<TF,2>& reice,
        Optical_props_2str_gpu<TF>& optical_props)
{
    const int ncol = clwp.dim(1);
    const int nlay = clwp.dim(2);
    const int nbnd = this->get_nband();

    Optical_props_2str_gpu<TF> clouds_liq(ncol, nlay, optical_props);
    Optical_props_2str_gpu<TF> clouds_ice(ncol, nlay, optical_props);

    // Set the mask.
    constexpr TF mask_min_value = TF(0.);
    const int block_col_m = 16;
    const int block_lay_m = 16;

    const int grid_col_m  = ncol/block_col_m + (ncol%block_col_m > 0);
    const int grid_lay_m  = nlay/block_lay_m + (nlay%block_lay_m > 0);

    dim3 grid_m_gpu(grid_col_m, grid_lay_m);
    dim3 block_m_gpu(block_col_m, block_lay_m);

    Array_gpu<BOOL_TYPE,2> liqmsk({ncol, nlay});
    set_mask<<<grid_m_gpu, block_m_gpu>>>(
            ncol, nlay, mask_min_value, liqmsk.ptr(), clwp.ptr());

    Array_gpu<BOOL_TYPE,2> icemsk({ncol, nlay});
    set_mask<<<grid_m_gpu, block_m_gpu>>>(
            ncol, nlay, mask_min_value, icemsk.ptr(), ciwp.ptr());

    // Temporary arrays for storage.
    Array_gpu<TF,3> ltau    ({ncol, nlay, nbnd});
    Array_gpu<TF,3> ltaussa ({ncol, nlay, nbnd});
    Array_gpu<TF,3> ltaussag({ncol, nlay, nbnd});

    Array_gpu<TF,3> itau    ({ncol, nlay, nbnd});
    Array_gpu<TF,3> itaussa ({ncol, nlay, nbnd});
    Array_gpu<TF,3> itaussag({ncol, nlay, nbnd});

    const int block_bnd = 14;
    const int block_lay = 1;
    const int block_col = 32;

    const int grid_bnd  = nbnd/block_bnd + (nbnd%block_bnd > 0);
    const int grid_lay  = nlay/block_lay + (nlay%block_lay > 0);
    const int grid_col  = ncol/block_col + (ncol%block_col > 0);

    dim3 grid_gpu(grid_bnd, grid_lay, grid_col);
    dim3 block_gpu(block_bnd, block_lay, block_col);

    // Liquid water
    compute_from_table_kernel<<<grid_gpu, block_gpu>>>(
            ncol, nlay, nbnd, liqmsk.ptr(), clwp.ptr(), reliq.ptr(),
            this->liq_nsteps, this->liq_step_size, this->radliq_lwr,
            this->lut_extliq_gpu.ptr(), this->lut_ssaliq_gpu.ptr(),
            this->lut_asyliq_gpu.ptr(), ltau.ptr(), ltaussa.ptr(), ltaussag.ptr());

    // Ice.
    compute_from_table_kernel<<<grid_gpu, block_gpu>>>(
            ncol, nlay, nbnd, icemsk.ptr(), ciwp.ptr(), reice.ptr(),
            this->ice_nsteps, this->ice_step_size, this->radice_lwr,
            this->lut_extice_gpu.ptr(), this->lut_ssaice_gpu.ptr(),
            this->lut_asyice_gpu.ptr(), itau.ptr(), itaussa.ptr(), itaussag.ptr());

    constexpr TF eps = std::numeric_limits<TF>::epsilon();

    combine_and_store_kernel<<<grid_gpu, block_gpu>>>(
            ncol, nlay, nbnd, eps,
            optical_props.get_tau().ptr(), optical_props.get_ssa().ptr(), optical_props.get_g().ptr(),
            ltau.ptr(), ltaussa.ptr(), ltaussag.ptr(),
            itau.ptr(), itaussa.ptr(), itaussag.ptr());
}

// 1scl variant of cloud optics.
template<typename TF>
void Cloud_optics_gpu<TF>::cloud_optics(
        const Array_gpu<TF,2>& clwp, const Array_gpu<TF,2>& ciwp,
        const Array_gpu<TF,2>& reliq, const Array_gpu<TF,2>& reice,
        Optical_props_1scl_gpu<TF>& optical_props)
{
    const int ncol = clwp.dim(1);
    const int nlay = clwp.dim(2);
    const int nbnd = this->get_nband();

    Optical_props_1scl_gpu<TF> clouds_liq(ncol, nlay, optical_props);
    Optical_props_1scl_gpu<TF> clouds_ice(ncol, nlay, optical_props);

    // Set the mask.
    constexpr TF mask_min_value = TF(0.);
    const int block_col_m = 16;
    const int block_lay_m = 16;

    const int grid_col_m  = ncol/block_col_m + (ncol%block_col_m > 0);
    const int grid_lay_m  = nlay/block_lay_m + (nlay%block_lay_m > 0);

    dim3 grid_m_gpu(grid_col_m, grid_lay_m);
    dim3 block_m_gpu(block_col_m, block_lay_m);

    Array_gpu<BOOL_TYPE,2> liqmsk({ncol, nlay});
    set_mask<<<grid_m_gpu, block_m_gpu>>>(
            ncol, nlay, mask_min_value, liqmsk.ptr(), clwp.ptr());

    Array_gpu<BOOL_TYPE,2> icemsk({ncol, nlay});
    set_mask<<<grid_m_gpu, block_m_gpu>>>(
            ncol, nlay, mask_min_value, icemsk.ptr(), ciwp.ptr());

    // Temporary arrays for storage.
    Array_gpu<TF,3> ltau    ({ncol, nlay, nbnd});
    Array_gpu<TF,3> ltaussa ({ncol, nlay, nbnd});
    Array_gpu<TF,3> ltaussag({ncol, nlay, nbnd});

    Array_gpu<TF,3> itau    ({ncol, nlay, nbnd});
    Array_gpu<TF,3> itaussa ({ncol, nlay, nbnd});
    Array_gpu<TF,3> itaussag({ncol, nlay, nbnd});

    const int block_bnd = 14;
    const int block_lay = 1;
    const int block_col = 32;

    const int grid_bnd  = nbnd/block_bnd + (nbnd%block_bnd > 0);
    const int grid_lay  = nlay/block_lay + (nlay%block_lay > 0);
    const int grid_col  = ncol/block_col + (ncol%block_col > 0);

    dim3 grid_gpu(grid_bnd, grid_lay, grid_col);
    dim3 block_gpu(block_bnd, block_lay, block_col);

    // Liquid water
    compute_from_table_kernel<<<grid_gpu, block_gpu>>>(
            ncol, nlay, nbnd, liqmsk.ptr(), clwp.ptr(), reliq.ptr(),
            this->liq_nsteps, this->liq_step_size, this->radliq_lwr,
            this->lut_extliq_gpu.ptr(), this->lut_ssaliq_gpu.ptr(),
            this->lut_asyliq_gpu.ptr(), ltau.ptr(), ltaussa.ptr(), ltaussag.ptr());

    // Ice.
    compute_from_table_kernel<<<grid_gpu, block_gpu>>>(
            ncol, nlay, nbnd, icemsk.ptr(), ciwp.ptr(), reice.ptr(),
            this->ice_nsteps, this->ice_step_size, this->radice_lwr,
            this->lut_extice_gpu.ptr(), this->lut_ssaice_gpu.ptr(),
            this->lut_asyice_gpu.ptr(), itau.ptr(), itaussa.ptr(), itaussag.ptr());

    constexpr TF eps = std::numeric_limits<TF>::epsilon();

    combine_and_store_kernel<<<grid_gpu, block_gpu>>>(
            ncol, nlay, nbnd, eps,
            optical_props.get_tau().ptr(),
            ltau.ptr(), ltaussa.ptr(),
            itau.ptr(), itaussa.ptr());
}

#ifdef FLOAT_SINGLE_RRTMGP
template class Cloud_optics_gpu<float>;
#else
template class Cloud_optics_gpu<double>;
#endif
