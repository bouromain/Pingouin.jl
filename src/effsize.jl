using Distributions
using Random
using Statistics
using StatsBase


function _check_eftype(eftype::String)::Bool
    return (eftype in ["none",
                       "cohen",
                       "hedges",
                       "glass",
                       "r",
                       "eta-square",
                       "odds-ratio",
                       "auc",
                       "cles"])
end


"""
Calculate effect size between two set of observations.

Parameters
----------
x : array
    First set of observations.
y : array
    Second set of observations.
paired : boolean
    If True, uses Cohen d-avg formula to correct for repeated measurements
    (see Notes).
eftype : string
    Desired output effect size.
    Available methods are:

    * ``'none'``: no effect size
    * ``'cohen'``: Unbiased Cohen d
    * ``'hedges'``: Hedges g
    * ``'glass'``: Glass delta
    * ``'r'``: correlation coefficient
    * ``'eta-square'``: Eta-square
    * ``'odds-ratio'``: Odds ratio
    * ``'auc'``: Area Under the Curve
    * ``'cles'``: Common Language Effect Size

Returns
-------
ef : float64
    Effect size

See Also
--------
convert_effsize : Conversion between effect sizes.
compute_effsize_from_t : Convert a T-statistic to an effect size.

Notes
-----
Missing values are automatically removed from the data. If ``x`` and ``y``
are paired, the entire row is removed.

If ``x`` and ``y`` are independent, the Cohen :math:`d` is:

.. math::

    d = \\frac{\\overline{X} - \\overline{Y}}
    {\\sqrt{\\frac{(n_{1} - 1)\\sigma_{1}^{2} + (n_{2} - 1)
    \\sigma_{2}^{2}}{n1 + n2 - 2}}}

If ``x`` and ``y`` are paired, the Cohen :math:`d_{avg}` is computed:

.. math::

    d_{avg} = \\frac{\\overline{X} - \\overline{Y}}
    {\\sqrt{\\frac{(\\sigma_1^2 + \\sigma_2^2)}{2}}}

The Cohen’s d is a biased estimate of the population effect size,
especially for small samples (n < 20). It is often preferable
to use the corrected Hedges :math:`g` instead:

.. math:: g = d \\times (1 - \\frac{3}{4(n_1 + n_2) - 9})

The Glass :math:`\\delta` is calculated using the group with the lowest
variance as the control group:

.. math::

    \\delta = \\frac{\\overline{X} -
    \\overline{Y}}{\\sigma^2_{\\text{control}}}

The common language effect size is the proportion of pairs where ``x`` is
higher than ``y`` (calculated with a brute-force approach where
each observation of ``x`` is paired to each observation of ``y``,
see `Pingouin.wilcoxon` for more details):

.. math:: \\text{CL} = P(X > Y) + .5 \\times P(X = Y)

For other effect sizes, Pingouin will first calculate a Cohen :math:`d` and
then use the `Pingouin.convert_effsize` to convert to the desired
effect size.

References
----------
* Lakens, D., 2013. Calculating and reporting effect sizes to
    facilitate cumulative science: a practical primer for t-tests and
    ANOVAs. Front. Psychol. 4, 863. https://doi.org/10.3389/fpsyg.2013.00863

* Cumming, Geoff. Understanding the new statistics: Effect sizes,
    confidence intervals, and meta-analysis. Routledge, 2013.

* https://osf.io/vbdah/

Examples
--------
1. Cohen d from two independent samples.

>>> x = [1, 2, 3, 4]
>>> y = [3, 4, 5, 6, 7]
>>> Pingouin.compute_effsize(x, y, paired=false, eftype="cohen")
-1.707825127659933

The sign of the Cohen d will be opposite if we reverse the order of
``x`` and ``y``:

>>> Pingouin.compute_effsize(y, x, paired=false, eftype="cohen")
1.707825127659933

2. Hedges g from two paired samples.

>>> x = [1, 2, 3, 4, 5, 6, 7]
>>> y = [1, 3, 5, 7, 9, 11, 13]
>>> Pingouin.compute_effsize(x, y, paired=true, eftype="hedges")
-0.8222477210374874

3. Glass delta from two independent samples. The group with the lowest
variance will automatically be selected as the control.

>>> Pingouin.compute_effsize(x, y, paired=false, eftype="glass")
-1.3887301496588271

4. Common Language Effect Size.

>>> Pingouin.compute_effsize(x, y, eftype="cles")
0.2857142857142857

In other words, there are ~29% of pairs where ``x`` is higher than ``y``,
which means that there are ~71% of pairs where ``x`` is *lower* than ``y``.
This can be easily verified by changing the order of ``x`` and ``y``:

>>> Pingouin.compute_effsize(y, x, eftype="cles")
0.7142857142857143
"""
function compute_effsize(x::Array{<:Number}, 
                         y::Array{<:Number};
                         paired::Bool=false,
                         eftype::String="cohen")::Float64
    if !_check_eftype(eftype)
        throw(DomainError(eftype, "Invalid eftype."))
    end

    if (size(x) != size(y)) && paired
        @warn "x and y have unequal sizes. Switching to paired = false."
        paired = false
    end

    # todo: remove na

    nx, ny = length(x), length(y)

    if ny == 1
    # Case 1: One-sample Test
        d = (mean(x) - mean(y)) / std(x)
        return d
    end

    if eftype == "glass"
    # Find group with lowest variance
        sd_control = minimum([std(x), std(y)])
        d = (mean(x) - mean(y)) / sd_control
        return d
    elseif eftype == "r"
    # return correlation coefficient (useful for CI bootstrapping)
        r = cor(x, y)
        return r
    elseif eftype == "cles"
    # Compute exact CLES (see Pingouin.wilcoxon)
        difference = x .- transpose(y)
        return mean(ifelse.(difference .== 0, 0.5, (difference .> 0) * 1.))
    else
    # Test equality of variance of data with a stringent threshold
    # equal_var, p = homoscedasticity(x, y, alpha=.001)
    # if !equal_var
    #     print("Unequal variances (p<.001). You should report",
    #           "Glass delta instead.")
    # end

    # Compute unbiased Cohen's d effect size
        if !paired
        # https://en.wikipedia.org/wiki/Effect_size
            ddof = nx + ny - 2
            poolsd = sqrt(((nx - 1) * var(x) + (ny - 1) * var(y)) / ddof)
            d = (mean(x) - mean(y)) / poolsd
        else
            d = (mean(x) - mean(y)) / sqrt((var(x) + var(y)) / 2)
        end

        return convert_effsize(d, "cohen", eftype, nx=nx, ny=ny)
    end
end


"""
Conversion between effect sizes.

Parameters
----------
ef : float64
    Original effect size.
input_type : string
    Effect size type of ef. Must be ``'r'`` or ``'d'``.
output_type : string
    Desired effect size type. Available methods are:

    * ``'cohen'``: Unbiased Cohen d
    * ``'hedges'``: Hedges g
    * ``'eta-square'``: Eta-square
    * ``'odds-ratio'``: Odds ratio
    * ``'AUC'``: Area Under the Curve
    * ``'none'``: pass-through (return ``ef``)

nx, ny : int, optional
    Length of vector x and y. Required to convert to Hedges g.

Returns
-------
ef : float
    Desired converted effect size

See Also
--------
compute_effsize : Calculate effect size between two set of observations.
compute_effsize_from_t : Convert a T-statistic to an effect size.

Notes
-----
The formula to convert **r** to **d** is given in [1]_:

.. math:: d = \\frac{2r}{\\sqrt{1 - r^2}}

The formula to convert **d** to **r** is given in [2]_:

.. math::

    r = \\frac{d}{\\sqrt{d^2 + \\frac{(n_x + n_y)^2 - 2(n_x + n_y)}
    {n_xn_y}}}

The formula to convert **d** to :math:`\\eta^2` is given in [3]_:

.. math:: \\eta^2 = \\frac{(0.5 d)^2}{1 + (0.5 d)^2}

The formula to convert **d** to an odds-ratio is given in [4]_:

.. math:: \\text{OR} = \\exp (\\frac{d \\pi}{\\sqrt{3}})

The formula to convert **d** to area under the curve is given in [5]_:

.. math:: \\text{AUC} = \\mathcal{N}_{cdf}(\\frac{d}{\\sqrt{2}})

References
----------
.. [1] Rosenthal, Robert. "Parametric measures of effect size."
    The handbook of research synthesis 621 (1994): 231-244.

.. [2] McGrath, Robert E., and Gregory J. Meyer. "When effect sizes
    disagree: the case of r and d." Psychological methods 11.4 (2006): 386.

.. [3] Cohen, Jacob. "Statistical power analysis for the behavioral
    sciences. 2nd." (1988).

.. [4] Borenstein, Michael, et al. "Effect sizes for continuous data."
    The handbook of research synthesis and meta-analysis 2 (2009): 221-235.

.. [5] Ruscio, John. "A probability-based measure of effect size:
    Robustness to base rates and other factors." Psychological methods 1
    3.1 (2008): 19.

Examples
--------
1. Convert from Cohen d to eta-square

>>> d = .45
>>> eta = Pingouin.convert_effsize(d, "cohen", "eta-square")
0.048185603807257595

2. Convert from Cohen d to Hegdes g (requires the sample sizes of each
    group)

>>> Pingouin.convert_effsize(.45, "cohen", "hedges", nx=10, ny=10)
0.4309859154929578

3. Convert Pearson r to Cohen d

>>> r = 0.40
>>> d = Pingouin.convert_effsize(r, "r", "cohen")
0.8728715609439696

4. Reverse operation: convert Cohen d to Pearson r

>>> Pingouin.convert_effsize(d, "cohen", "r")
0.4000000000000001
"""
function convert_effsize(ef::Float64,
                         input_type::String,
                         output_type::String;
                         nx::Union{Int64,Nothing}=nothing,
                         ny::Union{Int64,Nothing}=nothing)::Float64
    for eftype in [input_type, output_type]
        if !_check_eftype(eftype)
            throw(DomainError(eftype, "Invalid eftype."))
        end
    end

    if !(input_type in ["r", "cohen"])
        throw(DomainError(input_type, "Input type must be 'r' or 'cohen'"))
    end

    if input_type == output_type
        return ef
    end

# Convert r to Cohen d (Rosenthal 1994)
    d = input_type == "r" ? (2 * ef) / sqrt(1 - ef^2) : ef

# Then convert to the desired output type
    if output_type == "cohen"
        return d
    elseif output_type == "hedges"
        if all([v !== nothing for v in [nx, ny]])
            return d * (1 - (3 / (4 * (nx + ny) - 9)))
        else
            @warn "You need to pass nx and ny arguments to compute Hedges g. Returning Cohen's d instead"
            return d
        end
    elseif output_type == "glass"
        @warn "Returning original effect size instead of Glass because variance is not known."
        return ef
    elseif output_type == "r"
    # McGrath and Meyer 2006
        if all([v !== nothing for v in [nx, ny]])
            a = ((nx + ny)^2 - 2 * (nx + ny)) / (nx * ny)
        else
            a = 4
        end
        return d / sqrt(d^2 + a)
    elseif output_type == "eta-square"
    # Cohen 1988
        return (d / 2)^2 / (1 + (d / 2)^2)
    elseif output_type == "odds-ratio"
    # Borenstein et al. 2009
        return exp(d * pi / sqrt(3))
    else # "auc"
        cdf(Normal(), (d / sqrt(2)))
    end
end


"""
Compute effect size from a T-value.

Parameters
----------
tval : float
    T-value
nx, ny : int, optional
    Group sample sizes.
N : int, optional
    Total sample size (will not be used if nx and ny are specified)
eftype : string, optional
    desired output effect size

Returns
-------
ef : float
    Effect size

See Also
--------
compute_effsize : Calculate effect size between two set of observations.
convert_effsize : Conversion between effect sizes.

Notes
-----
If both nx and ny are specified, the formula to convert from *t* to *d* is:

.. math:: d = t * \\sqrt{\\frac{1}{n_x} + \\frac{1}{n_y}}

If only N (total sample size) is specified, the formula is:

.. math:: d = \\frac{2t}{\\sqrt{N}}

Examples
--------
1. Compute effect size from a T-value when both sample sizes are known.

>>> tval, nx, ny = 2.90, 35, 25
>>> d = Pingouin.compute_effsize_from_t(tval, nx=nx, ny=ny, eftype="cohen")
0.7593982580212534

2. Compute effect size when only total sample size is known (nx+ny)

>>> tval, N = 2.90, 60
>>> d = Pingouin.compute_effsize_from_t(tval, N=N, eftype="cohen")
0.7487767802667672
"""
function compute_effsize_from_t(tval::Float64;
                                nx::Union{Int64,Nothing}=nothing,
                                ny::Union{Int64,Nothing}=nothing,
                                N::Union{Int64,Nothing}=nothing,
                                eftype::String="cohen")::Float64
    if !_check_eftype(eftype)
        throw(DomainError(eftype, "Invalid eftype."))
    end

    if (nx !== nothing) && (ny !== nothing)
        d = tval * sqrt(1 / nx + 1 / ny)
    elseif N !== nothing
        d = 2 * tval / sqrt(N)
    else
        throw(DomainError(eftype, "You must specify either nx and ny, or just N"))
    end

    return convert_effsize(d, "cohen", eftype, nx=nx, ny=ny)
end


"""
Parametric confidence intervals around a Cohen d or a
correlation coefficient.

Parameters
----------
stat : float
    Original effect size. Must be either a correlation coefficient or a
    Cohen-type effect size (Cohen d or Hedges g).
nx, ny : int
    Length of vector x and y.
paired : bool
    Indicates if the effect size was estimated from a paired sample.
    This is only relevant for cohen or hedges effect size.
eftype : string
    Effect size type. Must be ``'r'`` (correlation) or ``'cohen'``
    (Cohen d or Hedges g).
confidence : float
    Confidence level (0.95 = 95%)
decimals : int
    Number of rounded decimals.

Returns
-------
ci : array
    Desired converted effect size

Notes
-----
To compute the parametric confidence interval around a
**Pearson r correlation** coefficient, one must first apply a
Fisher's r-to-z transformation:

.. math:: z = 0.5 \\cdot \\ln \\frac{1 + r}{1 - r} = \\text{arctanh}(r)

and compute the standard deviation:

.. math:: \\sigma = \\frac{1}{\\sqrt{n - 3}}

where :math:`n` is the sample size.

The lower and upper confidence intervals - *in z-space* - are then
given by:

.. math:: \\text{ci}_z = z \\pm \\text{crit} \\cdot \\sigma

where :math:`\\text{crit}` is the critical value of the normal distribution
corresponding to the desired confidence level (e.g. 1.96 in case of a 95%
confidence interval).

These confidence intervals can then be easily converted back to *r-space*:

.. math::

    \\text{ci}_r = \\frac{\\exp(2 \\cdot \\text{ci}_z) - 1}
    {\\exp(2 \\cdot \\text{ci}_z) + 1} = \\text{tanh}(\\text{ci}_z)

A formula for calculating the confidence interval for a
**Cohen d effect size** is given by Hedges and Olkin (1985, p86).
If the effect size estimate from the sample is :math:`d`, then it follows a
T distribution with standard deviation:

.. math::

    \\sigma = \\sqrt{\\frac{n_x + n_y}{n_x \\cdot n_y} +
    \\frac{d^2}{2 (n_x + n_y)}}

where :math:`n_x` and :math:`n_y` are the sample sizes of the two groups.

In one-sample test or paired test, this becomes:

.. math::

    \\sigma = \\sqrt{\\frac{1}{n_x} + \\frac{d^2}{2 n_x}}

The lower and upper confidence intervals are then given by:

.. math:: \\text{ci}_d = d \\pm \\text{crit} \\cdot \\sigma

where :math:`\\text{crit}` is the critical value of the T distribution
corresponding to the desired confidence level.

References
----------
* https://en.wikipedia.org/wiki/Fisher_transformation

* Hedges, L., and Ingram Olkin. "Statistical models for meta-analysis."
    (1985).

* http://www.leeds.ac.uk/educol/documents/00002182.htm

* https://www.ncbi.nlm.nih.gov/pmc/articles/PMC5133225/

Examples
--------
1. Confidence interval of a Pearson correlation coefficient

>>> x = [3, 4, 6, 7, 5, 6, 7, 3, 5, 4, 2]
>>> y = [4, 6, 6, 7, 6, 5, 5, 2, 3, 4, 1]
>>> nx, ny = length(x), length(y)
>>> stat = Pingouin.compute_effsize(x, y, eftype="r")
0.7468280049029223
>>> ci = Pingouin.compute_esci(stat=stat, nx=nx, ny=ny, eftype="r")
2-element Array{Float64,1}:
 0.27
 0.93

2. Confidence interval of a Cohen d

>>> stat = Pingouin.compute_effsize(x, y, eftype="cohen")
0.1537753990658328
>>> ci = Pingouin.compute_esci(stat=stat, nx=nx, ny=ny, eftype="cohen", decimals=3)
2-element Array{Float64,1}:
 -0.737
  1.045
"""
function compute_esci(;stat::Union{Float64, Nothing}=nothing,
                      nx::Union{Int64, Nothing}=nothing,
                      ny::Union{Int64, Nothing}=nothing,
                      paired::Bool=false,
                      eftype::String="cohen",
                      confidence::Float64=.95,
                      decimals::Int64=2)::Array{Float64}
    @assert eftype in ["r", "pearson", "spearman", "cohen", "d", "g", "hedges"]
    @assert (stat !== nothing) && (nx !== nothing)
    @assert 0 < confidence < 1

    if eftype in ["r", "pearson", "spearman"]
        z = atanh(stat)
        se = 1 / sqrt(nx - 3)
        crit = abs(quantile(Normal(), (1 - confidence) / 2))
        ci_z = [z - crit * se, z + crit * se]
        ci = tanh.(ci_z)
    else
        # Cohen d. Results are different than JASP which uses a non-central T
        # distribution. See github.com/jasp-stats/jasp-issues/issues/525
        if (ny == 1) || paired
            se = sqrt(1 / nx + stat^2 / (2 * nx))
            ddof = nx - 1
        else
            # Independent two-samples: give same results as R:
            # >>> cohen.d(..., paired = FALSE, noncentral=FALSE)
            se = sqrt(((nx + ny) / (nx * ny)) + (stat^2) / (2 * (nx + ny)))
            ddof = nx + ny - 2
        end
        crit = abs(quantile(TDist(ddof), (1 - confidence) / 2))
        ci = [stat - crit * se, stat + crit * se]
    end

    return round.(ci, digits=decimals)
end

"""
Bootstrapped confidence intervals of univariate and bivariate functions.

Parameters
----------
x : 1D-array
    First sample. Required for both bivariate and univariate functions.
y : 1D-array, nothing
    Second sample. Required only for bivariate functions.
func : str or custom function
    Function to compute the bootstrapped statistic.
    Accepted string values are:

    * ``'pearson'``: Pearson correlation (bivariate, requires x and y)
    * ``'spearman'``: Spearman correlation (bivariate)
    * ``'cohen'``: Cohen d effect size (bivariate)
    * ``'hedges'``: Hedges g effect size (bivariate)
    * ``'mean'``: Mean (univariate, requires only x)
    * ``'std'``: Standard deviation (univariate)
    * ``'var'``: Variance (univariate)
method : str
    Method to compute the confidence intervals:

    * ``'norm'``: Normal approximation with bootstrapped bias and
        standard error
    * ``'per'``: Basic percentile method
    * ``'cper'``: Bias corrected percentile method (default)
paired : boolean
    Indicates whether x and y are paired or not. Only useful when computing
    bivariate Cohen d or Hedges g bootstrapped confidence intervals.
confidence : float
    Confidence level (0.95 = 95%)
n_boot : int
    Number of bootstrap iterations. The higher, the better, the slower.
decimals : int
    Number of rounded decimals.
seed : int or None
    Random seed for generating bootstrap samples.
return_dist : boolean
    If True, return the confidence intervals and the bootstrapped
    distribution  (e.g. for plotting purposes).

Returns
-------
ci : array
    Desired converted effect size

Notes
-----
Results have been tested against the
`bootci <https://www.mathworks.com/help/stats/bootci.html>`_
Matlab function.

References
----------
* DiCiccio, T. J., & Efron, B. (1996). Bootstrap confidence intervals.
    Statistical science, 189-212.

* Davison, A. C., & Hinkley, D. V. (1997). Bootstrap methods and their
    application (Vol. 1). Cambridge university press.

Examples
--------
1. Bootstrapped 95% confidence interval of a Pearson correlation

>>> x = [3, 4, 6, 7, 5, 6, 7, 3, 5, 4, 2]
>>> y = [4, 6, 6, 7, 6, 5, 5, 2, 3, 4, 1]
>>> stat = cor(x, y)
0.7468280049029223
>>> ci = Pingouin.compute_bootci(x=x, y=y, func="pearson", seed=42)
2-element Array{Float64,1}:
 0.22
 0.93

2. Bootstrapped 95% confidence interval of a Cohen d

>>> stat = Pingouin.compute_effsize(x, y, eftype="cohen")
0.1537753990658328
>>> ci = Pingouin.compute_bootci(x, y=y, func="cohen", seed=42, decimals=3)
2-element Array{Float64,1}:
 -0.329
  0.589

3. Bootstrapped confidence interval of a standard deviation (univariate)

>>> stat = std(x)
1.6787441193290351
>>> ci = Pingouin.compute_bootci(x, func="std", seed=123)
2-element Array{Float64,1}:
 1.25
 2.2

4. Bootstrapped confidence interval using a custom univariate function

>>> skewness(x), Pingouin.compute_bootci(x, func=skewness, n_boot=10000, seed=123)
(-0.08244607271328411, [-1.01, 0.77])

5. Bootstrapped confidence interval using a custom bivariate function

>>> stat = sum(exp.(x) ./ exp.(y))
26.80405184881793
>>> ci = Pingouin.compute_bootci(x, y=y, func=f(x, y) = sum(exp.(x) ./ exp.(y)), n_boot=10000, seed=123)
>>> print(stat, ci)
2-element Array{Float64,1}:
 12.76
 45.52

6. Get the bootstrapped distribution around a Pearson correlation

>>> ci, bstat = Pingouin.compute_bootci(x, y=y, return_dist=true)
([0.27, 0.92], [0.6661370089058535, ...])
"""
function compute_bootci(x::Array{<:Number};
                        y::Union{Array{<:Number},Nothing}=nothing,
                        func::Union{Function, String}="pearson",
                        method::String="cper",
                        paired::Bool=false,
                        confidence::Float64=.95,
                        n_boot::Int64=2000,
                        decimals::Int64=2,
                        seed::Union{Int64, Nothing}=nothing,
                        return_dist::Bool=false)::Union{Array{<:Number},Tuple{Array{<:Number},Array{<:Number}}}
    n = length(x)
    @assert n > 1

    if y !== nothing
        ny = length(y)
        @assert ny > 1
        n = minimum([n, ny])
    end

    @assert 0 < confidence 1
    @assert method in ["norm", "normal", "percentile", "per", "cpercentile", "cper"]

    function _get_func(func::String)::Function
        if func == "pearson"
            return cor
        elseif func == "spearman"
            return corspearman
        elseif func in ["cohen", "hedges"]
            return f(x, y) = compute_effsize(x, y, paired=paired, eftype=func)
        elseif func == "mean"
            return mean
        elseif func == "std"
            return std
        elseif func == "var"
            return var
        else
            throw(DomainError(func, "Function string is not recognized."))
        end
    end

    if isa(func, String)
        func = _get_func(func)
    end

    # Bootstrap
    if seed !== nothing
        Random.seed!(seed)
    end
    bootsam = sample(1:n, (n, n_boot); replace=true, ordered=false)
    bootstat = Array{Float64,1}(undef, n_boot)

    if y !== nothing
        reference = func(x, y)
        for i in 1:n_boot
            # Note that here we use a bootstrapping procedure with replacement
            # of all the pairs (Xi, Yi). This is NOT suited for
            # hypothesis testing such as p-value estimation). Instead, for the
            # latter, one must only shuffle the Y values while keeping the X
            # values constant, i.e.:
            # >>> bootsam = rng.random_sample((n_boot, n)).argsort(axis=1)
            # >>> for i in range(n_boot):
            # >>>   bootstat[i] = func(x, y[bootsam[i, :]])
            bootstat[i] = func(x[bootsam[:, i]], y[bootsam[:, i]])
        end
    else
        reference = func(x)
        for i in 1:n_boot
            bootstat[i] = func(x[bootsam[:, i]])
        end
    end

    # Confidence Intervals
    α = 1 - confidence
    dist_sorted = sort(bootstat)

    if method in ["norm", "normal"]
        # Normal approximation
        za = quantile(Normal(), α/2)
        se = std(bootstat)

        bias = mean(bootstat .- reference)
        ll = reference - bias + se * za
        ul = reference - bias - se * za
        ci = [ll, ul]
    elseif method in ["percentile", "per"]
        # Uncorrected percentile
        pct_ll = trunc(Int, n_boot * (α/2))
        pct_ul = trunc(Int, n_boot * (1 - α/2))
        ci = [dist_sorted[pct_ll], dist_sorted[pct_ul]]
    else
        # Corrected percentile bootstrap
        # Compute bias-correction constant z0

        z_0 = quantile(Normal(), mean(bootstat .< reference) + mean(bootstat .== reference) / 2)
        z_α = quantile(Normal(), α/2)
        pct_ul = 100 * cdf(Normal(), 2 * z_0 - z_α)
        pct_ll = 100 * cdf(Normal(), 2 * z_0 + z_α)
        ll = percentile(bootstat, pct_ll)
        ul = percentile(bootstat, pct_ul)
        ci = [ll, ul]
    end

    ci = round.(ci, digits=decimals)
    if return_dist
        return ci, bootstat
    else
        return ci
    end
end
