# This source code is part of the Biotite package and is distributed
# under the 3-Clause BSD License. Please see 'LICENSE.rst' for further
# information.

"""
The module contains the `Sequence` superclass and `GeneralSequence`.
"""

__author__ = "Patrick Kunzmann"
__all__ = ["Sequence"]

import numpy as np
import abc
from .alphabet import Alphabet
from ..copyable import Copyable


_size_uint8  = np.iinfo(np.uint8 ).max +1
_size_uint16 = np.iinfo(np.uint16).max +1
_size_uint32 = np.iinfo(np.uint32).max +1


class Sequence(Copyable, metaclass=abc.ABCMeta):
    """
    The abstract base class for all sequence types.
    
    A `Sequence` can be seen as a succession of symbols, that are
    elements in the allowed set of symbols, the `Alphabet`. Internally,
    a `Sequence` object uses a `NumPy` `ndarray` of integers, where each
    integer represents a symbol. The `Alphabet` of a `Sequence` object
    is used to encode each symbol, that is used to create the
    `Sequence`, into an integer. These integer values are called
    symbol code, the encoding of an entire sequence of symbols is
    called sequence code.
    
    The size of the symbol code type in the array is determined by the 
    size of the `Alphabet`: If the `Alphabet` contains 256 symbols or
    less, one byte is used per array element; if the `Alphabet` contains
    between 257 and 65536 symbols, two bytes are used, and so on.
    
    Two `Sequence` objects are equal if they are instances of the same
    class, have the same `Alphabet` and have equal sequence codes.
    Comparison with a string or list of symbols evaluates always to
    false.
    
    A `Sequence` can be indexed by any 1-D index a `ndarray` accepts.
    If the index is a single integer, the decoded symbol at that
    position is returned, otherwise a subsequence is returned.
    
    Individual symbols of the sequence can also be exchanged in indexed
    form: If the an integer is used as index, the item is treated as a
    symbol. Any other index (slice, index list, boolean mask) expects
    multiple symbols, either as list of symbols, as `ndarray`
    containing a sequence code or another `Sequence` instance.
    Concatenation of two sequences is achieved with the '+' operator.
    
    Each subclass of `Sequence` needs to overwrite the abstract method
    `get_alphabet()`, which specifies the alphabet the `Sequence` uses.
    
    Parameters
    ----------
    sequence : iterable object, optional
        The symbol sequence, the `Sequence` is initialized with. For
        alphabets containing single letter strings, this parameter
        may also be a `str` object. By default the sequence is empty.
    
    Attributes
    ----------
    code : ndarray
        The sequence code of this `Sequence`
    symbols : list
        The list of symbols, represented by the `Sequence`.
        The list is generated by decoding the sequence code, when
        this attribute is accessed. When this attribute is modified,
        the new list of symbols is encoded into the sequence code.
    
    Examples
    --------
    Creating a DNA sequence from string and print the symbols and the
    code:
    
    >>> dna_seq = NucleotideSequence("ACGTA")
    >>> print(dna_seq)
    ACGTA
    >>> print(dna_seq.code)
    [0 1 2 3 0]
    >>> print(dna_seq.symbols)
    ['A', 'C', 'G', 'T', 'A']
    >>> print(list(dna_seq))
    ['A', 'C', 'G', 'T', 'A']
    
    Sequence indexing:
        
    >>> print(dna_seq[1:3])
    CG
    >>> print(dna_seq[[0,2,4]])
    AGA
    >>> print(dna_seq[np.array([False,False,True,True,True])])
    GTA
    
    Sequence manipulation:
        
    >>> dna_copy = dna_seq.copy()
    >>> dna_copy[2] = "C"
    >>> print(dna_copy)
    ACCTA
    >>> dna_copy = dna_seq.copy()
    >>> dna_copy[0:2] = dna_copy[3:5]
    >>> print(dna_copy)
    TAGTA
    >>> dna_copy = dna_seq.copy()
    >>> dna_copy[np.array([True,False,False,False,True])] = "T"
    >>> print(dna_copy)
    TCGTT
    >>> dna_copy = dna_seq.copy()
    >>> dna_copy[1:4] = np.array([0,1,2])
    >>> print(dna_copy)
    AACGA
    
    Concatenate the two sequences:
        
    >>> dna_seq_concat = dna_seq + dna_seq_rev
    >>> print(dna_seq_concat)
    ACGTAATGCA
        
    """
    
    def __init__(self, sequence=[]):
        self.symbols = sequence
        
    
    def copy(self, new_seq_code=None):
        """
        Copy the object.
        
        Parameters
        ----------
        new_seq_code : ndarray, optional
            If this parameter is set, the sequence code is set to this
            value, rather than the original sequence code.
        
        Returns
        -------
        copy
            A copy of this object.
        """
        # Override in order to achieve better performance,
        # in case only a subsequence is needed,
        # because not the entire sequence code is copied then
        clone = self.__copy_create__()
        if new_seq_code is None:
            clone.code = np.copy(self.code)
        else:
            clone.code = new_seq_code
        self.__copy_fill__(clone)
        return clone
    
    @property
    def symbols(self):
        return self.get_alphabet().decode_multiple(self.code)
    
    @symbols.setter
    def symbols(self, value):
        alph = self.get_alphabet()
        dtype = Sequence._dtype(len(alph))
        self._seq_code = alph.encode_multiple(value, dtype)
    
    @property
    def code(self):
        return self._seq_code
    
    @code.setter
    def code(self, value):
        dtype = Sequence._dtype(len(self.get_alphabet()))
        self._seq_code = value.astype(dtype, copy=False)
    
    
    @abc.abstractmethod
    def get_alphabet(self):
        """
        Get the `Alphabet` of the `Sequence`.
        
        This method must be overwritten, when subclassing `Sequence`.
        
        Returns
        -------
        alphabet : Alphabet
            `Sequence` alphabet.
        """
        pass
    
    def reverse(self):
        """
        Reverse the `Sequence`.
        
        Returns
        -------
        reversed : Sequence
            The reversed `Sequence`.
            
        Examples
        --------
            
        >>> dna_seq = DNASequence("ACGTA")
        >>> dna_seq_rev = dna_seq.reverse()
        >>> print(dna_seq_rev)
        ATGCA
        """
        reversed_code = np.flip(np.copy(self._seq_code), axis=0)
        reversed = self.copy(reversed_code)
        return reversed
    
    def is_valid(self):
        """
        Check, if the sequence contains a valid sequence code.
        
        A sequence code is valid, if at each sequence position the
        code is smaller than the size of the alphabet.
        
        Invalid code means that the code cannot be decoded into
        symbols. Furthermore invalid code can lead to serious
        errors in alignments, since the substitution matrix
        is indexed with an invalid index.
        
        Returns
        -------
        valid : bool
            True, if the sequence is valid, false otherwise.
        """
        return (self.code < len(self.get_alphabet())).all()
    
    def get_symbol_frequency(self):
        """
        Get the number of occurences of each symbol in the sequence.
        
        If a symbol does not occur in the sequence, but it is in the
        alphabet, its number of occurences is 0.
        
        Returns
        -------
        frequency : dict
            A dictionary containing the symbols as keys and the
            corresponding number of occurences in the sequence as
            values.
        """
        frequencies = {}
        for code, symbol in enumerate(self.get_alphabet()):
            frequencies[symbol] = len(np.nonzero((self._seq_code == code))[0])
        return frequencies
    
    def __getitem__(self, index):
        alph = self.get_alphabet()
        sub_seq = self._seq_code.__getitem__(index)
        if isinstance(sub_seq, np.ndarray):
            return self.copy(sub_seq)
        else:
            return alph.decode(sub_seq)
    
    def __setitem__(self, index, item):
        alph = self.get_alphabet()
        if isinstance(index, int):
            # Expect a single symbol
            code = alph.encode(item)
            self._seq_code.__setitem__(index, code)
        else:
            # Expect multiple symbols
            if isinstance(item, Sequence):
                code = item.code
            elif isinstance(item, np.ndarray):
                code = item
            else:
                # Default: item is iterable object of symbols
                code = alph.encode_multiple(item)
            self._seq_code.__setitem__(index, code)
    
    def __len__(self):
        return len(self._seq_code)
    
    def __iter__(self):
        alph = self.get_alphabet()
        i = 0
        while i < len(self):
            yield alph.decode(self._seq_code[i])
            i += 1
    
    def __eq__(self, item):
        if not isinstance(item, type(self)):
            return False
        if self.get_alphabet() != item.get_alphabet():
            return False
        return np.array_equal(self._seq_code, item._seq_code)
    
    def __ne__(self, item):
        return not self == item
    
    def __str__(self):
        alph = self.get_alphabet()
        return "".join([alph.decode(e) for e in self._seq_code])
    
    def __add__(self, sequence):
        if self.get_alphabet().extends(sequence.get_alphabet()):
            new_code = np.concatenate((self._seq_code, sequence._seq_code))
            new_seq = self.copy(new_code)
            return new_seq
        elif sequence.get_alphabet().extends(self.get_alphabet()):
            new_code = np.concatenate((self._seq_code, sequence._seq_code))
            new_seq = sequence.copy(new_code)
            return new_seq
        else:
            raise ValueError("The sequences alphabets are not compatible")

    @staticmethod
    def _dtype(alphabet_size):
        if alphabet_size <= _size_uint8:
            return np.uint8
        elif alphabet_size <= _size_uint16:
            return np.uint16
        elif alphabet_size <= _size_uint32:
            return np.uint32
        else:
            return np.uint64
