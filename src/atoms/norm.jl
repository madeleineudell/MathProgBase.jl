import Base.abs

export norm, abs, norm_inf, norm_2, square, sum_squared, norm_1, quad_form, quad_over_lin, qol_elementwise

function check_size(x::AbstractCvxExpr)
  if x.size[1] > 1 && x.size[2] > 1
    error("norm(x) not supported when x has size $(x.size)")
  end
end

function promote_vexity(x::AbstractCvxExpr)
  if x.vexity == :constant
    return :constant
  elseif x.vexity == :linear
    return :convex
  elseif x.vexity == :convex && x.sign == :pos
    return :convex
  elseif x.vexity == :concave && x.sign == :neg
    return :convex
  else
    error("norm(x) is not DCP compliant when x has curvature $(x.vexity) and sign $(x.sign)")
  end
end

function norm_inf(x::AbstractCvxExpr)
  check_size(x)
  vexity = promote_vexity(x)
  this = CvxExpr(:norm_inf, [x], vexity, :pos, (1, 1))

  # 'x <= this' will try to find the canon_form for 'this', so we need to initialize it
  this.canon_form = ()->CanonicalConstr[]
  canon_constr_array = (x <= this).canon_form()
  append!(canon_constr_array, (-this <= x).canon_form())
  this.canon_form = ()->canon_constr_array
  return this
end

function quad_form(x::Constant, A::Constant)
  return x'*A*x
end

function quad_form(x::Constant, A::AbstractCvxExpr)
  return x'*A*x
end

function quad_form(x::AbstractCvxExpr, A::Constant)
  if A.size[1] != A.size[2]
    error("Quadratic form only takes square matrices")
  end
  if !issym(full(A.value))
    error("Quadratic form only defined for symmetric matrices")
  end
  V = eigvals(full(A.value))
  if !all(V .>= 0) && !all(V .<= 0)
    error("Quadratic forms supported only for semidefinite matrices")
  end
  
  if all(V .>= 0)
    factor = 1
  else
    factor = -1
  end

  P = sqrtm(full(factor*A.value))
  return factor*square(norm_2(P*x))
end

quad_form(x::Value, A::Value) = quad_form(convert(CvxExpr, x), convert(CvxExpr, A))
quad_form(x::Value, A::AbstractCvxExpr) = quad_form(convert(CvxExpr, x), A)
quad_form(x::AbstractCvxExpr, A::Value) = quad_form(x, convert(CvxExpr, A))


function check_size_qol(x::AbstractCvxExpr, y::AbstractCvxExpr)
  if (x.size[1] > 1 && x.size[2] > 1) || y.size != (1, 1)
    error("quad_over_lin arguments must be a vector and a scalar")
  end
end

function quad_over_lin(x::Constant, y::Constant)
  #TODO sign/size checks
  return x'*x/y
end

function quad_over_lin(x::Constant, y::AbstractCvxExpr)
  #TODO vexity and sign checks
  this = CvxExpr(:quad_over_lin, [x, y], :convex, :pos, (1, 1))
  x_size = get_vectorized_size(x)
  cone_size = x_size + 2
  
  # (y + t, y - t, 2x) socp constraint
  coeffs1 = spzeros(cone_size, 1)
  coeffs1[1] = -1
  coeffs1[2] = -1
  coeffs2 = spzeros(cone_size, 1)
  coeffs2[1] = -1
  coeffs2[2] = 1
  cone_coeffs = VecOrMatOrSparse[coeffs1, coeffs2]
  cone_vars = [y.uid, this.uid]
  cone_constant = [0; 0; 2*vec(x.value)]

  # y >= 0 linear constraint
  lin_coeffs = VecOrMatOrSparse[-speye(1)]
  lin_vars = [y.uid]
  lin_constant = zeros(1, 1)

  canon_constr_array = [CanonicalConstr(cone_coeffs, cone_vars, cone_constant, false, true),
                        CanonicalConstr(lin_coeffs, lin_vars, lin_constant, false, false)]
  append!(canon_constr_array, y.canon_form())
  this.canon_form = ()->canon_constr_array

  return this
end

function quad_over_lin(x::AbstractCvxExpr, y::Constant)
  #TODO vexity and sign checks
  this = CvxExpr(:quad_over_lin, [x, y], :convex, :pos, (1, 1))
  x_size = get_vectorized_size(x)
  cone_size = x_size + 2
  
  # (y + t, y - t, 2x) socp constraint
  coeffs1 = [spzeros(2, x_size); -2*speye(x_size)]
  coeffs2 = spzeros(cone_size, 1)
  coeffs2[1] = -1
  coeffs2[2] = 1
  cone_coeffs = VecOrMatOrSparse[coeffs1, coeffs2]
  cone_vars = [x.uid, this.uid]
  cone_constant = [y.value[1]; y.value[1]; zeros(x_size, 1)]

  canon_constr_array = [CanonicalConstr(cone_coeffs, cone_vars, cone_constant, false, true)]
  append!(canon_constr_array, x.canon_form())
  this.canon_form = ()->canon_constr_array

  return this
end

function quad_over_lin(x::AbstractCvxExpr, y::AbstractCvxExpr)
  #TODO vexity and sign checks
  this = CvxExpr(:quad_over_lin, [x, y], :convex, :pos, (1, 1))
  x_size = get_vectorized_size(x)
  cone_size = x_size + 2

  # (y + t, y - t, 2x) socp constraint
  coeffs1 = [spzeros(2, x_size); -2*speye(x_size)]
  coeffs2 = spzeros(cone_size, 1)
  coeffs2[1] = -1
  coeffs2[2] = -1
  coeffs3 = spzeros(cone_size, 1)
  coeffs3[1] = -1
  coeffs3[2] = 1
  cone_coeffs = VecOrMatOrSparse[coeffs1, coeffs2, coeffs3]
  cone_vars = [x.uid, y.uid, this.uid]
  cone_constant = zeros(cone_size, 1)

  # y >= 0 linear constraint
  lin_coeffs = VecOrMatOrSparse[-speye(1)]
  lin_vars = [y.uid]
  lin_constant = zeros(1, 1)

  canon_constr_array = [CanonicalConstr(cone_coeffs, cone_vars, cone_constant, false, true),
                        CanonicalConstr(lin_coeffs, lin_vars, lin_constant, false, false)]
  append!(canon_constr_array, x.canon_form())
  append!(canon_constr_array, y.canon_form())
  this.canon_form = ()->canon_constr_array

  return this
end

quad_over_lin(x::Value, y::Value) = quad_over_lin(convert(CvxExpr, x), convert(CvxExpr, y))
quad_over_lin(x::Value, y::AbstractCvxExpr) = quad_over_lin(convert(CvxExpr, x), y)
quad_over_lin(x::AbstractCvxExpr, y::Value) = quad_over_lin(x, convert(CvxExpr, y))

function qol_elementwise(x::Constant, y::Constant)
  return Constant((x.value.^2)./y.value, :pos)
end

function qol_elementwise(x::Constant, y::AbstractCvxExpr)
  #TODO vexity and sign checks
  this = CvxExpr(:qol_elementwise, [x, y], :convex, :pos, x.size)
  x_size = get_vectorized_size(x)

  canon_constr_array = CanonicalConstr[]
  for i = 1:x_size
    coeffs1 = spzeros(3, x_size)
    coeffs1[1, i] = -1
    coeffs1[2, i] = -1
    coeffs2 = spzeros(3, x_size)
    coeffs2[1, i] = -1
    coeffs2[2, i] = 1
    cone_coeffs = VecOrMatOrSparse[coeffs1, coeffs2]
    cone_vars = [y.uid, this.uid]
    cone_constant = [0; 0; 2*x.value[i]]
    push!(canon_constr_array, CanonicalConstr(cone_coeffs, cone_vars, cone_constant, false, true))
  end
  
  # y >= 0 linear constraint
  lin_coeffs = VecOrMatOrSparse[-speye(x_size)]
  lin_vars = [y.uid]
  lin_constant = zeros(x_size, 1)
  push!(canon_constr_array, CanonicalConstr(lin_coeffs, lin_vars, lin_constant, false, false))
  append!(canon_constr_array, y.canon_form())
  this.canon_form = ()->canon_constr_array

  return this
end

function qol_elementwise(x::AbstractCvxExpr, y::Constant)
  #TODO vexity and sign checks
  this = CvxExpr(:qol_elementwise, [x, y], :convex, :pos, x.size)
  x_size = get_vectorized_size(x)

  canon_constr_array = CanonicalConstr[]
  for i = 1:x_size
    coeffs1 = spzeros(3, x_size)
    coeffs1[3, i] = -2
    coeffs2 = spzeros(3, x_size)
    coeffs2[1, i] = -1
    coeffs2[2, i] = 1
    cone_coeffs = VecOrMatOrSparse[coeffs1, coeffs2]
    cone_vars = [x.uid, this.uid]
    cone_constant = [y.value[i], y.value[i], 0]
    push!(canon_constr_array, CanonicalConstr(cone_coeffs, cone_vars, cone_constant, false, true))
  end
  
  append!(canon_constr_array, x.canon_form())
  this.canon_form = ()->canon_constr_array

  return this
end

function qol_elementwise(x::AbstractCvxExpr, y::AbstractCvxExpr)
  #TODO vexity and sign checks
  this = CvxExpr(:qol_elementwise, [x, y], :convex, :pos, x.size)
  x_size = get_vectorized_size(x)

  canon_constr_array = CanonicalConstr[]
  for i = 1:x_size
    coeffs1 = spzeros(3, x_size)
    coeffs1[3, i] = -2
    coeffs2 = spzeros(3, x_size)
    coeffs2[1, i] = -1
    coeffs2[2, i] = -1
    coeffs3 = spzeros(3, x_size)
    coeffs3[1, i] = -1
    coeffs3[2, i] = 1
    cone_coeffs = VecOrMatOrSparse[coeffs1, coeffs2, coeffs3]
    cone_vars = [x.uid, y.uid, this.uid]
    cone_constant = zeros(3, 1)
    push!(canon_constr_array, CanonicalConstr(cone_coeffs, cone_vars, cone_constant, false, true))
  end
  
  # y >= 0 linear constraint
  lin_coeffs = VecOrMatOrSparse[-speye(x_size)]
  lin_vars = [y.uid]
  lin_constant = zeros(x_size, 1)
  push!(canon_constr_array, CanonicalConstr(lin_coeffs, lin_vars, lin_constant, false, false))
  append!(canon_constr_array, x.canon_form())
  append!(canon_constr_array, y.canon_form())
  this.canon_form = ()->canon_constr_array

  return this
end

qol_elementwise(x::Value, y::Value) = qol_elementwise(convert(CvxExpr, x), convert(CvxExpr, y))
qol_elementwise(x::Value, y::AbstractCvxExpr) = qol_elementwise(convert(CvxExpr, x), y)
qol_elementwise(x::AbstractCvxExpr, y::Value) = qol_elementwise(x, convert(CvxExpr, y))

function geo_mean(x::AbstractCvxExpr, y::AbstractCvxExpr)
  #TODO vexity and sign checks
  this = CvxExpr(:geo_mean, [x, y], :concave, :pos, x.size)
  x_size = get_vectorized_size(x)

  canon_constr_array = CanonicalConstr[]
  for i = 1:x_size
    coeffs1 = spzeros(3, x_size)
    coeffs1[1, i] = -1
    coeffs1[1, i] = 1
    coeffs2 = spzeros(3, x_size)
    coeffs2[1, i] = -1
    coeffs2[2, i] = -1
    coeffs3 = spzeros(3, x_size)
    coeffs3[3, i] = -2
    cone_coeffs = VecOrMatOrSparse[coeffs1, coeffs2, coeffs3]
    cone_vars = [x.uid, y.uid, this.uid]
    cone_constant = zeros(3, 1)
    push!(canon_constr_array, CanonicalConstr(cone_coeffs, cone_vars, cone_constant, false, true))
  end
  
  # x,y >= 0 linear constraint
  lin_coeffs1 = VecOrMatOrSparse[-speye(x_size)]
  lin_vars1 = [y.uid]
  lin_constant1 = zeros(x_size, 1)
  lin_coeffs2 = VecOrMatOrSparse[-speye(x_size)]
  lin_vars2 = [x.uid]
  lin_constant2 = zeros(x_size, 1)
  push!(canon_constr_array, CanonicalConstr(lin_coeffs1, lin_vars1, lin_constant1, false, false))
  push!(canon_constr_array, CanonicalConstr(lin_coeffs2, lin_vars2, lin_constant2, false, false))
  append!(canon_constr_array, x.canon_form())
  append!(canon_constr_array, y.canon_form())
  this.canon_form = ()->canon_constr_array

  return this
end

function sqrt(x::AbstractCvxExpr)
  return geo_mean(x, ones(x.size...))
end

function inv_pos(x::AbstractCvxExpr)
  return qol_elementwise(ones(x.size...), x)
end

function sum_squared(x::AbstractCvxExpr)
  return square(norm_2(x))
end

function square(x::AbstractCvxExpr)
  return qol_elementwise(x, ones(x.size...))
end

function norm_1(x::AbstractCvxExpr)
  return sum(abs(x))
end

# TODO: Look at matrix
function norm_2(x::AbstractCvxExpr)
  check_size(x)
  vexity = promote_vexity(x)
  this = CvxExpr(:norm_2, [x], vexity, :pos, (1, 1))
  cone_size = get_vectorized_size(x) + 1

  coeffs1 = spzeros(cone_size, 1)
  coeffs1[1] = -1
  coeffs2 = [spzeros(1, get_vectorized_size(x)); -speye(get_vectorized_size(x))]
  coeffs =  VecOrMatOrSparse[coeffs1, coeffs2]
  vars = [this.uid, x.uid]
  constant = zeros(cone_size, 1)

  canon_constr_array = [CanonicalConstr(coeffs, vars, constant, false, true)]
  append!(canon_constr_array, x.canon_form())
  this.canon_form = ()->canon_constr_array

  return this
end

# TODO: Everything
function norm(x::AbstractCvxExpr, p = 2)
  norm_map = {1=>:norm1, 2=>:norm2, :inf=>:norm_inf, :nuc=>:norm_nuc}
  norm_type = norm_map[p]
  if x.vexity == :constant
    return CvxExpr(norm_type,[x],:constant,:pos,(1,1))
  elseif x.vexity == :linear
    return CvxExpr(norm_type,[x],:convex,:pos,(1,1))
  elseif x.vexity == :convex && x.sign == :pos
    return CvxExpr(norm_type,[x],:convex,:pos,(1,1))
  elseif x.vexity == :concave && x.sign == :neg
    return CvxExpr(norm_type,[x],:convex,:pos,(1,1))
  else
    error("norm(x) is not DCP compliant when x has curvature $(x.vexity) and sign $(x.sign)")
  end
end

### elementwise

function abs(x::AbstractCvxExpr)
  if x.vexity == :constant
    this = CvxExpr(:abs,[x],:constant,:pos,x.size)
  elseif x.vexity == :linear
    if x.sign == :pos
      this = CvxExpr(:abs,[x],:linear,:pos,x.size)
    elseif x.sign == :neg
      this = CvxExpr(:abs,[x],:linear,:pos,x.size)
    else
      this = CvxExpr(:abs,[x],:convex,:pos,x.size)
    end
  elseif x.vexity == :convex && x.sign == :pos
    this = CvxExpr(:abs,[x],:convex,:pos,x.size)
  elseif x.vexity == :concave && x.sign == :neg
    this = CvxExpr(:abs,[x],:convex,:pos,x.size)
  else
    error("abs(x) is not DCP compliant when x has curvature $(x.vexity) and sign $(x.sign)")
  end

  println(this.vexity)
  # 'x <= this' will try to find the canon_form for 'this', so we need to initialize it
  this.canon_form = ()->CanonicalConstr[]
  canon_constr_array = (x <= this).canon_form()
  append!(canon_constr_array, (-this <= x).canon_form())
  this.canon_form = ()->canon_constr_array
  return this
end