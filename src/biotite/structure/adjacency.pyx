# Copyright 2017 Patrick Kunzmann.
# This source code is part of the Biotite package and is distributed under the
# 3-Clause BSD License. Please see 'LICENSE.rst' for further information.

"""
This module allows efficient search of atoms in a defined radius around
a location.
"""

cimport cython
cimport numpy as np
from libc.stdlib cimport realloc, malloc, free

from .atoms import AtomArray
import numpy as np
from .geometry import distance

ctypedef np.uint64_t ptr
ctypedef np.float32_t float32

__all__ = ["AdjacencyMap"]


cdef class AdjacencyMap:
    """
    This class enables the efficient search of atoms in vicinity of a
    defined location.
    
    This class stores the indices of an atom array in virtual "boxes",
    each corresponding to a specific coordinate interval. If the atoms
    in vicinity of a specific location are searched, only the atoms in
    the relevant boxes are checked. Effectively this decreases the
    operation time from *O(n)* to *O(1)*, after the `AdjacencyMap` has been
    created. Therefore an `AdjacencyMap` saves calculation time in those
    cases, where vicinity is checked for multiple locations.
    
    Parameters
    ----------
    atom_array : AtomArray
        The `AtomArray` to create the `AdjacencyMap` for.
    box_size: float
        The coordinate interval each box has for x, y and z axis.
        The amount of boxes depend on the protein size and the
        `box_size`.
            
    Examples
    --------
    
    >>> adj_map = AdjacencyMap(atom_array, box_size=5)
    >>> near_atoms = atom_array[adj_map.get_atoms([1,2,3], radius=7)]
    """
    
    cdef float32[:,:] _coord
    cdef ptr[:,:,:] _boxes
    cdef ptr[:,:,:] _box_length
    cdef int _boxsize
    cdef float32[:] _min_coord
    cdef float32[:] _max_coord
    cdef int[:] _box_count
    cdef int _max_box_length
    
    def __init__(self, AtomArray atom_array not None, int box_size):
        cdef float32 x, y, z
        cdef int i, j, k
        cdef int atom_array_i
        cdef int* box_ptr = 0
        cdef int length
        self._coord = atom_array.coord.astype(np.float32)
        self._boxsize = box_size
        # calculate how many boxes are required for each dimension
        min_coord = np.min(self.array.coord, axis=0).astype(np.float32)
        max_coord = np.max(self.array.coord, axis=0).astype(np.float32)
        self._min_coord = min_coord
        self._max_coord = max_coord
        self._box_count = ((max_coord - min_coord) // box_size) +1
        # ndarray of pointers to C-arrays
        # containing indices to atom array
        # First deallocate, just to make sure
        # (Constructor might be called multiple times)
        if self._boxes is None:
            deallocate_ptrs(self._boxes)
        self._boxes = np.zeros(self.box_count, dtype=np.uint64)
        # Stores the length of the C-arrays
        self._box_length = np.zeros(self.box_count, dtype=np.int32)
        # Fill boxes
        for atom_array_i in range(self._coord.shape[0]):
            x = self._coord[atom_array_i, 0]
            y = self._coord[atom_array_i, 1]
            z = self._coord[atom_array_i, 2]
            # Get box indices for coordinates
            self._get_box_index(x, y, z, &i, &j, &k)
            # Increment box length and reallocate
            length = self._box_length[i,j,k] + 1
            box_ptr = <int*>self._boxes[i,j,k]
            box_ptr = <int*>realloc(box_ptr, length * sizeof(int))
            if not box_ptr:
                raise MemoryError()
            # Potentially increase max box length
            if length > self._max_box_length:
                self._max_box_length = length
            # Store atom array index in respective box
            box_ptr[length-1] = atom_array_i
            # Store new box pointer and length
            self._box_length[i,j,k] = length
            self._boxes[i,j,k] = <ptr> box_ptr
            
    def __dealloc__():
        deallocate_ptrs(self._boxes)
    
    def get_atoms(self, np.ndarray coord, float32 radius):
        """
        Search for atoms in vicinity of the given position.
        
        Parameters
        ----------
        coord : ndarray, dtype=float
            The central coordinates, around which the atoms are
            searched.
        radius: float
            The radius around `coord`, in which the atoms are searched,
            i.e. all atoms in `radius` distance to `coord` are returned.
        
        Returns
        -------
        indices : ndarray, dtype=int
            The indices of the atom array, where the atoms are in the
            defined vicinity around `coord`.
            
        See Also
        --------
        get_atoms_in_box
        """
        cdef np.ndarray indices = \
            self.get_atoms_in_box(coord, int(radius/self.boxsize)+1)
        cdef np.ndarray sel_coord = np.asarray(self._coord[indices])
        dist = distance(sel_coord, coord)
        return indices[dist <= radius]
    
    def get_atoms_in_box(self, np.ndarray coord,
                         int box_r=1,
                         bint efficient_mode=False,
                         np.ndarray array_indices=None):
        """
        Search for atoms in vicinity of the given box.
        
        This is more efficient than `get_atoms()`.
        
        Parameters
        ----------
        coord : ndarray, dtype=float
            The central coordinates, around which the atoms are
            searched.
        box_r: float, optional
            The radius around `coord` (in amount of boxes), in which
            the atoms are searched. This does not correspond to the
            Euclidian distance used in `get_atoms()`. In this case, all
            atoms in the box corresponding to `coord` and in adjacent
            boxes are returned.
            By default atoms are searched in the box of `coord`
            and adjacent boxes.
        efficient_mode : bool, optional
            If enabled, the method will be much more efficient for
            multiple calls of this method with the same `box_r`.
            Rather than creating a new `ndarray` buffer for the
            indices, the indices will be put into the provided
            `array_indices` buffer.
            (Default: false)
        array_indices : ndarray, dtype=int, optional
            If provided, the method will put the indices into the
            buffer of this `ndarray`.
            This increases the performance for multiple
            calls, since no new `ndarray` needs to be created.
            Note, that the array needs sufficient size (larger than
            the actual amount of resulting indices), that is dependent
            on `box_r`.
            When you call the method the first time in
            `efficient_mode`, leave this parameter out, a reusable
            array of sufficient size will be created for you.
            Has no effect if `efficient_mode` is false.
            The array will only be partly updated with meaningful
            values. The range of the array, that is filled with
            meaningful values is returned in `length`.
        
        Returns
        -------
        indices : ndarray, dtype=int
            The indices of the atom array, where the atoms are in the
            defined vicinity around `coord`. If `efficient_mode`
            is enabled. the `length` return value gives the range of
            `indices`, that is filled with meaningful values.
        length : int, optional
            Exclusive range of meaningful values in `efficient_mode`.
            
        See Also
        --------
        get_atoms
        """
        # Pessimistic assumption on index array length requirement
        cdef int length
        cdef int index_array_length = (2*box_r + 1)**3 * self._max_box_length
        cdef int[:] indices
        if not efficient_mode or array_indices is None:
            indices = np.zeros(index_array_length,
                                                 dtype=np.int32):
        else:
            # Check if index array has sufficient size and dtype
            if array_indices.dtype != np.int32 \
                or len(array_indices) < index_array_length:
                    raise ValueError("Optionally provided index array"
                                     "is insufficient")
            indices = array_indices
        # Fill index array
        length = self._get_atoms_in_box(coord.astype(float32, copy=False),
                                        indices, box_r)
        if not efficient_mode:
            return np.asarray(indices[:length])
        else:
            return np.asarray(indices), length
    
    
    def _get_atoms_in_box(self,
                          float32[:] coord not None,
                          int[:] indices not None
                          int box_r=1):
        cdef int length
        cdef int* ptr
        cdef float32 x, y,z
        cdef int i, j, k
        cdef int adj_i, adj_j, adj_k
        cdef int array_i, box_i
        x = coord[0]
        y = coord[1]
        z = coord[2]
        if not self._check_coord(x, y, z):
            raise ValueError("Coordinates are not in range of box")
        self._get_box_index(x, y, z, &i, &j, &k)
        array_i = 0
        # Look into boxes of the indices and adjacent boxes
        # in all 3 dimensions
        for adj_i in range(i-box_r, i+box_r+1):
            if (adj_i >= 0 and adj_i < shape[0]):
                for adj_j in range(j-box_r, j+box_r+1):
                    if (adj_j >= 0 and adj_j < shape[1]):
                        for adj_k in range(k-box_r, k+box_r+1):
                            if (adj_k >= 0 and adj_k < shape[2]):
                                # Fill with index array
                                # with indices in box
                                ptr = <int*>self._boxes[i,j,k]
                                length = self._box_length[i,j,k]
                                for box_i in range(length):
                                    indices[array_i] = ptr[box_i]
                                    array_i += 1
        # return the actual length of the index array
        return array_i
    
    
    cdef inline void _get_box_index(self, float32 x, float32 y, float32 z,
                             int* i, int* j, int* k):
        i[0] = (x - self._min_coord[0]) // self._boxsize
        j[0] = (y - self._min_coord[1]) // self._boxsize
        k[0] = (z - self._min_coord[2]) // self._boxsize
    
    
    cdef inline bint _check_coord(self, float32 x, float32 y, float32 z):
        if x < self._min_coord[0] or x > self._max_coord[0]:
            return False
        if y < self._min_coord[1] or y > self._max_coord[1]:
            return False
        if z < self._min_coord[2] or z > self._max_coord[2]:
            return False
        return True


cdef inline deallocate_ptrs(ptr[:,:,:] ptrs):
    cdef int i, j, k
    cdef int* box_ptr
    # Free box pointers
    for i in ptrs.shape[0]:
        for j in ptrs.shape[1]:
            for k in ptrs.shape[2]:
                box_ptr = <int*>ptrs[i,j,k]
                free(box_ptr)