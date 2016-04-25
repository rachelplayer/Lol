{-# LANGUAGE FlexibleContexts, GADTs, NoImplicitPrelude,
             PartialTypeSignatures, RebindableSyntax, ScopedTypeVariables
             #-}

module Verify where

import           Beacon
import           Common
import qualified Crypto.Lol.RLWE.Continuous as C
import qualified Crypto.Lol.RLWE.Discrete   as D
import qualified Crypto.Lol.RLWE.RLWR       as R

import Crypto.Challenges.RLWE.Proto.RLWE.Challenge
import Crypto.Challenges.RLWE.Proto.RLWE.ChallengeType
import Crypto.Challenges.RLWE.Proto.RLWE.InstanceCont
import Crypto.Challenges.RLWE.Proto.RLWE.InstanceDisc
import Crypto.Challenges.RLWE.Proto.RLWE.InstanceRLWR
import Crypto.Challenges.RLWE.Proto.RLWE.SampleCont
import Crypto.Challenges.RLWE.Proto.RLWE.SampleDisc
import Crypto.Challenges.RLWE.Proto.RLWE.SampleRLWR
import Crypto.Challenges.RLWE.Proto.RLWE.Secret

import Crypto.Lol             hiding (RRq, lift)
import Crypto.Lol.Types.Proto

import           Control.Applicative
import           Control.Monad.Except
import qualified Data.ByteString.Lazy as BS
import           Data.List            (nub)
import           Data.Maybe
import           Data.Reflection      hiding (D)

import Net.Beacon

import System.Directory (doesFileExist)

-- Tensor type used to verify instances
type T = CT

-- | Verifies all instances in the challenge tree, given the path to the
-- root of the tree.
verifyMain :: FilePath -> IO ()
verifyMain path = do
  -- get a list of challenges to reveal
  challs <- challengeList path

  -- verifies challenges and accumulates beacon positions for each challenge
  beaconAddrs <- mapM (verifyChallenge path) challs

  -- verifies that all challenges use distinct beacon addresses
  when (all isJust beaconAddrs) $ printPassFail "Checking for distinct beacon addresses..." "DISTINCT" $
    throwErrorIf (length (nub beaconAddrs) /= length beaconAddrs) "Beacon addresses overlap"

-- | Reads a challenge and verifies all instances that have a secret.
-- Returns the beacon address for the challenge.
verifyChallenge :: FilePath -> String -> IO (Maybe BeaconAddr)
verifyChallenge path challName = printPassFail ("Verifying challenge " ++ challName ++ ":\n") "DONE" $ do
  (beacon, insts) <- readChallenge path challName
  mapM_ verifyInstanceU insts
  return $ Just beacon

-- | Read a challenge from a file. Outputs the beacon address for this
-- challenge and a list of instances to be verified.
readChallenge :: (MonadIO m)
  => FilePath -> String -> ExceptT String m (BeaconAddr, [InstanceU])
readChallenge path challName = do
  let challFile = challFilePath path challName
  c <- readProtoType challFile
  isAvail <- isBeaconAvailable $ beaconTime c

  if isAvail
  then do
    liftIO $ putStrLn
      "Current time is past the beacon time: expecting suppressed input."
    readSuppressedChallenge path challName c
  else do
    liftIO $ putStrLn
      "The beacon is not yet available. Verifying all instances..."
    readFullChallenge path challName c

readSuppressedChallenge :: (MonadIO m)
  => FilePath -> String -> Challenge -> ExceptT String m (BeaconAddr, [InstanceU])
readSuppressedChallenge path challName (Challenge ccid numInsts time offset challType) = do
  let numInsts' = fromIntegral numInsts
  beacon <- readBeacon path time
  let deletedID = suppressedSecretID numInsts beacon offset
  let delSecretFile = secretFilePath path challName deletedID
  delSecretExists <- liftIO $ doesFileExist delSecretFile
  throwErrorIf delSecretExists $
    "Secret " ++ show deletedID ++
    " should not exist, but it does! You may need to run the 'reveal' phase."
  insts <- mapM (readInstanceU challType path challName ccid) $
    filter (/= deletedID) $ take numInsts' [0..]
  checkParamsEq challName "numInstances" (numInsts'-1) (length insts)
  return (BA time offset, insts)

readFullChallenge :: (MonadIO m)
  => FilePath -> String -> Challenge -> ExceptT String m (BeaconAddr, [InstanceU])
readFullChallenge path challName (Challenge ccid numInsts time offset challType) = do
  let numInsts' = fromIntegral numInsts
  insts <- mapM (readInstanceU challType path challName ccid) $ take numInsts' [0..]
  checkParamsEq challName "numInstances" numInsts' (length insts)
  return (BA time offset, insts)

-- | Read an 'InstanceU' from a file.
readInstanceU :: (MonadIO m)
                 => ChallengeType -> FilePath -> String
                 -> ChallengeID -> InstanceID -> ExceptT String m InstanceU
readInstanceU challType path challName cid1 iid1 = do
  let secFile = secretFilePath path challName iid1
  sec@(Secret cid2 iid2 m q s) <- readProtoType secFile
  checkParamsEq secFile "challID" cid1 cid2
  checkParamsEq secFile "instID" iid1 iid2
  let instFile = instFilePath path challName iid1
      validateParams cid' iid' m' q' = do
        checkParamsEq instFile "challID" cid1 cid'
        checkParamsEq instFile "instID" iid1 iid'
        checkParamsEq instFile "m" m m'
        checkParamsEq instFile "q" q q'
  case challType of
    Cont -> do
      inst@(InstanceCont cid' iid' m' q' _ _ _) <- readProtoType instFile
      validateParams cid' iid' m' q'
      return $ IC sec inst
    Disc -> do
      inst@(InstanceDisc cid' iid' m' q' _ _ _) <- readProtoType instFile
      validateParams cid' iid' m' q'
      return $ ID sec inst
    RLWR -> do
      inst@(InstanceRLWR cid' iid' m' q' _ _) <- readProtoType instFile
      validateParams cid' iid' m' q'
      return $ IR sec inst

checkParamsEq :: (Monad m, Show a, Eq a)
  => String -> String -> a -> a -> ExceptT String m ()
checkParamsEq data' param expected actual =
  throwErrorIfNot (expected == actual) $ "Error while reading " ++
    data' ++ ": " ++ param ++ " mismatch. Expected " ++
    show expected ++ " but got " ++ show actual

-- | Verify an 'InstanceU'.
verifyInstanceU :: (Monad m) => InstanceU -> ExceptT String m ()

verifyInstanceU (IC (Secret _ _ _ _ s) (InstanceCont _ _ m q _ bound samples)) =
  reifyFactI (fromIntegral m) (\(_::proxy m) ->
    reify (fromIntegral q :: Int64) (\(_::Proxy q) -> do
      s' :: Cyc T m (Zq q) <- fromProto s
      samples' :: [C.Sample _ _ _ (RRq q)] <- fromProto $
        fmap (\(SampleCont a b) -> (a,b)) samples
      throwErrorIfNot (validInstanceCont bound s' samples')
        "A continuous RLWE sample exceeded the error bound."))

verifyInstDisc (ID (Secret _ _ _ _ s) (InstanceDisc _ _ m q _ bound samples)) =
  reifyFactI (fromIntegral m) (\(_::proxy m) ->
    reify (fromIntegral q :: Int64) (\(_::Proxy q) -> do
      s' :: Cyc T m (Zq q) <- fromProto s
      samples' <- fromProto $ fmap (\(SampleDisc a b) -> (a,b)) samples
      throwErrorIfNot (validInstanceDisc bound s' samples')
        "A discrete RLWE sample exceeded the error bound."))

verifyInstRLWR (IR (Secret _ _ _ _ s) (InstanceRLWR _ _ m q p samples)) =
  reifyFactI (fromIntegral m) (\(_::proxy m) ->
    reify (fromIntegral q :: Int64) (\(_::Proxy q) ->
      reify (fromIntegral p :: Int64) (\(_::Proxy p) -> do
        s' :: Cyc T m (Zq q) <- fromProto s
        samples' :: [R.Sample _ _ _ (Zq p)] <- fromProto $
          fmap (\(SampleRLWR a b) -> (a,b)) samples
        throwErrorIfNot (validInstanceRLWR s' samples')
          "An RLWR sample was invalid.")))

-- | Read an XML file for the beacon corresponding to the provided time.
readBeacon :: (MonadIO m) => FilePath -> BeaconEpoch -> ExceptT String m Record
readBeacon path time = do
  let file = xmlFilePath path time
  checkFileExists file
  rec' <- liftIO $ fromXML <$> BS.readFile file
  maybeThrowError rec' $ "Could not parse " ++ file

-- | Test if the 'gSqNorm' of the error for each RLWE sample in the
-- instance (given the secret) is less than the given bound.
validInstanceCont ::
  (C.RLWECtx t m zq rrq, Ord (LiftOf rrq), Ring (LiftOf rrq))
  => LiftOf rrq -> Cyc t m zq -> [C.Sample t m zq rrq] -> Bool
validInstanceCont bound s = all ((bound > ) . (C.errorGSqNorm s))

-- | Test if the 'gSqNorm' of the error for each RLWE sample in the
-- instance (given the secret) is less than the given bound.
validInstanceDisc :: (D.RLWECtx t m zq)
                     => LiftOf zq -> Cyc t m zq -> [D.Sample t m zq] -> Bool
validInstanceDisc bound s = all ((bound > ) . (D.errorGSqNorm s))

-- | Test if the given RLWR instance is valid for the given secret.
validInstanceRLWR :: (R.RLWRCtx t m zq zp, Eq zp)
  => Cyc t m zq -> [R.Sample t m zq zp] -> Bool
validInstanceRLWR s = let s' = adviseCRT s in all (validSampleRLWR s')

-- | Test if the given RLWR sample is valid for the given secret.
validSampleRLWR :: (R.RLWRCtx t m zq zp, Eq zp)
  => Cyc t m zq -> R.Sample t m zq zp -> Bool
validSampleRLWR s (a,b) = b == R.roundedProd s a