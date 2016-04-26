{-# LANGUAGE ViewPatterns #-}
-- | Calculation of confidence intervals
module Statistics.ConfidenceInt (
    poissonCI
  , binomialCI
  , naiveBinomialCI
  ) where

import Statistics.Distribution
import Statistics.Distribution.ChiSquared
import Statistics.Distribution.Beta
import Statistics.Types



-- | Calculate confidence intervals for Poisson-distributed value for
--   single measurement. These are exact confidence intervals
poissonCI :: CL Double -> Int -> Estimate ConfInt Double
poissonCI cl@(getPValue -> p) n
  | n <  0    = error "Statistics.ConfidenceInt.poissonErr: negative number of trials"
  | n == 0    = estimateFromInterval m (m1,m2) cl
  | otherwise = estimateFromInterval m (m1,m2) cl
  where
    m  = fromIntegral n
    m1 = 0.5 * quantile (chiSquared (2*n  )) (p/2)
    m2 = 0.5 * quantile (chiSquared (2*n+2)) (1 - p/2)

-- | Calculate confidence interval using normal approximation. Note
--   that this approximation breaks down when /p/ is either close to 0
--   or to 1. In particular if @np < 5@ or @1 - np < 5@ this
--   approximation shouldn't be used.
naiveBinomialCI :: Int         -- ^ Number of trials
                -> Int         -- ^ Number of successes
                -> Estimate NormalErr Double
naiveBinomialCI n k
  | n <= 0 || k < 0 = error "Statistics.ConfidenceInt.naiveBinomialCI: negative number of events"
  | k > n           = error "Statistics.ConfidenceInt.naiveBinomialCI: more successes than trials"
  | otherwise       = estimateNormErr eff σ
  where
    eff = fromIntegral k / fromIntegral n
    σ   = eff * (1 - eff) / fromIntegral n


-- | Clopper-Pearson confidence interval also known as exact
--   confidence intervals.
binomialCI :: CL Double
           -> Int               -- ^ Number of trials
           -> Int               -- ^ Number of successes
           -> Estimate ConfInt Double
binomialCI cl@(getPValue -> p) ni ki
  | ni <= 0 || ki < 0 = error "Statistics.ConfidenceInt.binomialCI: negative number of events"
  | ki > ni           = error "Statistics.ConfidenceInt.binomialCI: more successes than trials"
  | ki == 0           = estimateFromInterval eff (0, ub) cl
  | ni == ki          = estimateFromInterval eff (lb,0 ) cl
  | otherwise         = estimateFromInterval eff (lb,ub) cl
  where
    k   = fromIntegral ki
    n   = fromIntegral ni
    eff = k / n
    ub  = 1 - quantile (betaDistr (n - k)     (k + 1)) (p/2)
    lb  = 1 - quantile (betaDistr (n - k + 1)  k     ) (1 - p/2)


{-
Brown, Lawrence D.; Cai, T. Tony; DasGupta, Anirban
(2001). "Interval Estimation for a Binomial Proportion". Statistical
Science 16 (2): 101–133. doi:10.1214/ss/1009213286. MR 1861069. Zbl
02068924.
-}