{-# LANGUAGE BangPatterns, DeriveDataTypeable, FlexibleInstances, MultiParamTypeClasses #-}
{-# OPTIONS_GHC  -fno-warn-unused-imports #-}
module Challenges.Proto.DiscLWESample (DiscLWESample(..)) where
import Prelude ((+), (/))
import qualified Prelude as Prelude'
import qualified Data.Typeable as Prelude'
import qualified Data.Data as Prelude'
import qualified Text.ProtocolBuffers.Header as P'
import qualified Crypto.Lol.Types.Proto.Rq as Lol (Rq)

data DiscLWESample = DiscLWESample{a :: !(Lol.Rq), b :: !(Lol.Rq)}
                   deriving (Prelude'.Show, Prelude'.Eq, Prelude'.Ord, Prelude'.Typeable, Prelude'.Data)

instance P'.Mergeable DiscLWESample where
  mergeAppend (DiscLWESample x'1 x'2) (DiscLWESample y'1 y'2) = DiscLWESample (P'.mergeAppend x'1 y'1) (P'.mergeAppend x'2 y'2)

instance P'.Default DiscLWESample where
  defaultValue = DiscLWESample P'.defaultValue P'.defaultValue

instance P'.Wire DiscLWESample where
  wireSize ft' self'@(DiscLWESample x'1 x'2)
   = case ft' of
       10 -> calc'Size
       11 -> P'.prependMessageSize calc'Size
       _ -> P'.wireSizeErr ft' self'
    where
        calc'Size = (P'.wireSizeReq 1 11 x'1 + P'.wireSizeReq 1 11 x'2)
  wirePut ft' self'@(DiscLWESample x'1 x'2)
   = case ft' of
       10 -> put'Fields
       11 -> do
               P'.putSize (P'.wireSize 10 self')
               put'Fields
       _ -> P'.wirePutErr ft' self'
    where
        put'Fields
         = do
             P'.wirePutReq 10 11 x'1
             P'.wirePutReq 18 11 x'2
  wireGet ft'
   = case ft' of
       10 -> P'.getBareMessageWith update'Self
       11 -> P'.getMessageWith update'Self
       _ -> P'.wireGetErr ft'
    where
        update'Self wire'Tag old'Self
         = case wire'Tag of
             10 -> Prelude'.fmap (\ !new'Field -> old'Self{a = P'.mergeAppend (a old'Self) (new'Field)}) (P'.wireGet 11)
             18 -> Prelude'.fmap (\ !new'Field -> old'Self{b = P'.mergeAppend (b old'Self) (new'Field)}) (P'.wireGet 11)
             _ -> let (field'Number, wire'Type) = P'.splitWireTag wire'Tag in P'.unknown field'Number wire'Type old'Self

instance P'.MessageAPI msg' (msg' -> DiscLWESample) DiscLWESample where
  getVal m' f' = f' m'

instance P'.GPB DiscLWESample

instance P'.ReflectDescriptor DiscLWESample where
  getMessageInfo _ = P'.GetMessageInfo (P'.fromDistinctAscList [10, 18]) (P'.fromDistinctAscList [10, 18])
  reflectDescriptorInfo _
   = Prelude'.read
      "DescriptorInfo {descName = ProtoName {protobufName = FIName \".Lwe.DiscLWESample\", haskellPrefix = [], parentModule = [MName \"Lwe\"], baseName = MName \"DiscLWESample\"}, descFilePath = [\"Lwe\",\"DiscLWESample.hs\"], isGroup = False, fields = fromList [FieldInfo {fieldName = ProtoFName {protobufName' = FIName \".Lwe.DiscLWESample.a\", haskellPrefix' = [], parentModule' = [MName \"Lwe\",MName \"DiscLWESample\"], baseName' = FName \"a\", baseNamePrefix' = \"\"}, fieldNumber = FieldId {getFieldId = 1}, wireTag = WireTag {getWireTag = 10}, packedTag = Nothing, wireTagLength = 1, isPacked = False, isRequired = True, canRepeat = False, mightPack = False, typeCode = FieldType {getFieldType = 11}, typeName = Just (ProtoName {protobufName = FIName \".Lol.Rq\", haskellPrefix = [], parentModule = [MName \"Lol\"], baseName = MName \"Rq\"}), hsRawDefault = Nothing, hsDefault = Nothing},FieldInfo {fieldName = ProtoFName {protobufName' = FIName \".Lwe.DiscLWESample.b\", haskellPrefix' = [], parentModule' = [MName \"Lwe\",MName \"DiscLWESample\"], baseName' = FName \"b\", baseNamePrefix' = \"\"}, fieldNumber = FieldId {getFieldId = 2}, wireTag = WireTag {getWireTag = 18}, packedTag = Nothing, wireTagLength = 1, isPacked = False, isRequired = True, canRepeat = False, mightPack = False, typeCode = FieldType {getFieldType = 11}, typeName = Just (ProtoName {protobufName = FIName \".Lol.Rq\", haskellPrefix = [], parentModule = [MName \"Lol\"], baseName = MName \"Rq\"}), hsRawDefault = Nothing, hsDefault = Nothing}], descOneofs = fromList [], keys = fromList [], extRanges = [], knownKeys = fromList [], storeUnknown = False, lazyFields = False, makeLenses = False}"

instance P'.TextType DiscLWESample where
  tellT = P'.tellSubMessage
  getT = P'.getSubMessage

instance P'.TextMsg DiscLWESample where
  textPut msg
   = do
       P'.tellT "a" (a msg)
       P'.tellT "b" (b msg)
  textGet
   = do
       mods <- P'.sepEndBy (P'.choice [parse'a, parse'b]) P'.spaces
       Prelude'.return (Prelude'.foldl (\ v f -> f v) P'.defaultValue mods)
    where
        parse'a
         = P'.try
            (do
               v <- P'.getT "a"
               Prelude'.return (\ o -> o{a = v}))
        parse'b
         = P'.try
            (do
               v <- P'.getT "b"
               Prelude'.return (\ o -> o{b = v}))