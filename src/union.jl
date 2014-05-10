export VecOrMatOrSparse, VecOrMatOrSparseOrNothing, Value, ArrayFloat64OrNothing

# Contains all user defined Unions
VecOrMatOrSparse = Union(Vector, Matrix, SparseMatrixCSC)
VecOrMatOrSparseOrNothing = Union(Vector, Matrix, SparseMatrixCSC, Nothing)
ArrayFloat64OrNothing = Union(Array{Float64, }, Nothing)
Value = Union(Number,AbstractArray)
