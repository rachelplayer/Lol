{-# LANGUAGE DataKinds, FlexibleContexts,
             NoImplicitPrelude, RebindableSyntax,
             ScopedTypeVariables, TypeFamilies,
             TypeOperators, UndecidableInstances #-}

module TensorBenches (tensorBenches) where

import Apply.Cyc
import Benchmarks
import Utils

import Crypto.Lol
import Crypto.Lol.Cyclotomic.Tensor
import Crypto.Lol.Types

tensorBenches :: IO Benchmark
tensorBenches = benchGroup "Tensor" [
  benchGroup "l" $ applyBasic (Proxy::Proxy QuickParams) $ hideArgs bench_l]

-- convert input from Dec basis to Pow basis
bench_l :: (Tensor t, Fact m, Additive r, TElt t r, NFData (t m r)) => t m r -> Bench '(t,m,r)
bench_l = bench l

type QuickTest = '[ '(F128, Zq 257),
                    '(F32 * F9, Zq 577),
                    '(F32 * F9, Int64) ]
type Tensors = '[CT,RT]
type QuickParams = ( '(,) <$> Tensors) <*> QuickTest
