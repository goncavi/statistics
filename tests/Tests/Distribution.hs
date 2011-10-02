{-# OPTIONS_GHC -fno-warn-orphans #-}
{-# LANGUAGE ScopedTypeVariables #-}
module Tests.Distribution (
    distributionTests
  ) where

import Control.Applicative
import Control.Exception

import Data.List     (find)
import Data.Typeable (Typeable)

import Test.Framework                       (Test,testGroup)
import Test.Framework.Providers.QuickCheck2 (testProperty)
import Test.QuickCheck         as QC
import Test.QuickCheck.Monadic as QC
import Text.Printf

import Statistics.Distribution
import Statistics.Distribution.Binomial
import Statistics.Distribution.ChiSquared
import Statistics.Distribution.CauchyLorentz
import Statistics.Distribution.Exponential
import Statistics.Distribution.Gamma
import Statistics.Distribution.Geometric
import Statistics.Distribution.Hypergeometric
import Statistics.Distribution.Normal
import Statistics.Distribution.Poisson
import Statistics.Distribution.Uniform

import Prelude hiding (catch)

import Tests.Helpers


-- | Tests for all distributions
distributionTests :: Test
distributionTests = testGroup "Tests for all distributions"
  [ contDistrTests (T :: T CauchyDistribution      )
  , contDistrTests (T :: T ChiSquared              )
  , contDistrTests (T :: T ExponentialDistribution )
  , contDistrTests (T :: T GammaDistribution       )
  , contDistrTests (T :: T NormalDistribution      )
  , contDistrTests (T :: T UniformDistribution     )
    
  , discreteDistrTests (T :: T BinomialDistribution       )
  , discreteDistrTests (T :: T GeometricDistribution      )
  , discreteDistrTests (T :: T HypergeometricDistribution )
  , discreteDistrTests (T :: T PoissonDistribution        )

  , unitTests
  ]

----------------------------------------------------------------
-- Tests
----------------------------------------------------------------

-- Tests for continous distribution
contDistrTests :: (ContDistr d, QC.Arbitrary d, Typeable d, Show d) => T d -> Test
contDistrTests t = testGroup ("Tests for: " ++ typeName t) $
  cdfTests t ++
  [ testProperty "PDF sanity"              $ pdfSanityCheck   t
  , testProperty "Quantile is CDF inverse" $ quantileIsInvCDF t
  , testProperty "quantile fails p<0||p>1" $ quantileShouldFail t
  ]

-- Tests for discrete distribution
discreteDistrTests :: (DiscreteDistr d, QC.Arbitrary d, Typeable d, Show d) => T d -> Test
discreteDistrTests t = testGroup ("Tests for: " ++ typeName t) $
  cdfTests t ++
  [ testProperty "Prob. sanity"         $ probSanityCheck       t
  , testProperty "CDF is sum of prob."  $ discreteCDFcorrect    t
  ]

-- Tests for distributions which have CDF
cdfTests :: (Distribution d, QC.Arbitrary d, Show d) => T d -> [Test]
cdfTests t =
  [ testProperty "C.D.F. sanity"        $ cdfSanityCheck         t
  , testProperty "CDF limit at +∞"      $ cdfLimitAtPosInfinity  t
  , testProperty "CDF limit at -∞"      $ cdfLimitAtNegInfinity  t
  , testProperty "CDF is nondecreasing" $ cdfIsNondecreasing     t
  , testProperty "1-CDF is correct"     $ cdfComplementIsCorrect t
  ]
----------------------------------------------------------------

-- CDF is in [0,1] range
cdfSanityCheck :: (Distribution d) => T d -> d -> Double -> Bool
cdfSanityCheck _ d x = c >= 0 && c <= 1 
  where c = cumulative d x

-- CDF never decreases
cdfIsNondecreasing :: (Distribution d) => T d -> d -> Double -> Double -> Bool
cdfIsNondecreasing _ d = monotonicallyIncreasesIEEE $ cumulative d

-- CDF limit at +∞ is 1
cdfLimitAtPosInfinity :: (Distribution d) => T d -> d -> Bool
cdfLimitAtPosInfinity _ d = printTestCase ("Last elements: " ++ show (drop 990 probs))
                          $ Just 1.0 == (find (>=1) probs)
  where
    probs = take 1000 $ map (cumulative d) $ iterate (*1.4) 1)

-- CDF limit at -∞ is 0
cdfLimitAtNegInfinity :: (Distribution d) => T d -> d -> Property
cdfLimitAtNegInfinity _ d = printTestCase ("Last elements: " ++ show (drop 990 probs))
                          $ Just 0.0 == (find (<=0) probs)
  where
    probs = take 1000 $ map (cumulative d) $ iterate (*1.4) (-1)

-- CDF's complement is implemented correctly
cdfComplementIsCorrect :: (Distribution d) => T d -> d -> Double -> Bool
cdfComplementIsCorrect _ d x = (eq 1e-14) 1 (cumulative d x + complCumulative d x)


-- PDF is positive
pdfSanityCheck :: (ContDistr d) => T d -> d -> Double -> Bool
pdfSanityCheck _ d x = p >= 0
  where p = density d x

-- Quantile is inverse of CDF
quantileIsInvCDF :: (ContDistr d) => T d -> d -> Double -> Property
quantileIsInvCDF _ d p =
  p > 0 && p < 1  ==> ( printTestCase (printf "Quantile     = %g" q )
                      $ printTestCase (printf "Probability  = %g" p )
                      $ printTestCase (printf "Probability' = %g" p')
                      $ printTestCase (printf "Error        = %e" (abs $ p - p'))
                      $ abs (p - p') < 1e-14
                      )
  where
    q  = quantile   d p
    p' = cumulative d q

-- Test that quantile fails if p<0 or p>1
quantileShouldFail :: (ContDistr d) => T d -> d -> Double -> Property
quantileShouldFail _ d p =
  p < 0 || p > 1 ==> QC.monadicIO $ do r <- QC.run $ catch
                                              (do { return $! quantile d p; return False })
                                              (\(e :: SomeException) -> return True)
                                       QC.assert r


-- Probability is in [0,1] range
probSanityCheck :: (DiscreteDistr d) => T d -> d -> Int -> Bool
probSanityCheck _ d x = p >= 0 && p <= 1 
  where p = probability d x

-- Check that discrete CDF is correct
discreteCDFcorrect :: (DiscreteDistr d) => T d -> d -> Int -> Int -> Property
discreteCDFcorrect _ d a b = 
  abs (a - b) < 100  ==>  abs (p1 - p2) < 3e-10
  -- Avoid too large differeneces. Otherwise there is to much to sum
  --
  -- Absolute difference is used guard againist precision loss when
  -- close values of CDF are subtracted
  where
    n  = min a b
    m  = max a b
    p1 = cumulative d (fromIntegral m + 0.5) - cumulative d (fromIntegral n - 0.5)
    p2 = sum $ map (probability d) [n .. m]


    
----------------------------------------------------------------
-- Arbitrary instances for ditributions
----------------------------------------------------------------

instance QC.Arbitrary BinomialDistribution where
  arbitrary = binomial <$> QC.choose (1,100) <*> QC.choose (0,1)
instance QC.Arbitrary ExponentialDistribution where
  arbitrary = exponential <$> QC.choose (0,100)
instance QC.Arbitrary GammaDistribution where
  arbitrary = gammaDistr <$> QC.choose (0.1,10) <*> QC.choose (0.1,10)
instance QC.Arbitrary GeometricDistribution where
  arbitrary = geometric <$> QC.choose (0,1)
instance QC.Arbitrary HypergeometricDistribution where
  arbitrary = do l <- QC.choose (1,20)
                 m <- QC.choose (0,l)
                 k <- QC.choose (1,l)
                 return $ hypergeometric m l k
instance QC.Arbitrary NormalDistribution where
  arbitrary = normalDistr <$> QC.choose (-100,100) <*> QC.choose (1e-3, 1e3)
instance QC.Arbitrary PoissonDistribution where
  arbitrary = poisson <$> QC.choose (0,1)
instance QC.Arbitrary ChiSquared where
  arbitrary = chiSquared <$> QC.choose (1,100)
instance QC.Arbitrary UniformDistribution where
  arbitrary = do a <- QC.arbitrary
                 b <- QC.arbitrary `suchThat` (/= a)
                 return $ uniformDistr a b
instance QC.Arbitrary CauchyDistribution where
  arbitrary = cauchyDistribution
                <$> arbitrary
                <*> ((abs <$> arbitrary) `suchThat` (> 0))

----------------------------------------------------------------
-- Unit tests
----------------------------------------------------------------

unitTests :: Test
unitTests = testGroup "Unit tests"
  [ testAssertion "density (gammaDistr 150 1/150) 1 == 4.883311" $
      4.883311418525483 =~ (density (gammaDistr 150 (1/150)) 1)
  ]
