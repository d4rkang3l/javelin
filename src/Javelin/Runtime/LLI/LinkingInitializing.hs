module Javelin.Runtime.LLI.LinkingInitializing
where

import qualified Data.Map.Lazy as Map (fromList, Map, lookup, insert, (!))
import Data.Array.IArray as Array ((!), (//))
import Data.Word (Word16)
import Control.Applicative ((<$>))
import Control.Arrow ((>>>))
import Javelin.Util

import Javelin.Runtime.Structures
import Javelin.Runtime.DescSign
import Javelin.ByteCode.Data
import Data.Either.Utils (maybeToEither)


linking :: ClassName -> Runtime -> Either VMError Runtime
linking name rt = verify name rt >>= prepare name



-- §5.4.1 Verify
verify :: ClassName -> Runtime -> Either VMError Runtime
verify name rt = Right rt

-- §5.4.2 Preparation
prepare :: ClassName -> Runtime -> Either VMError Runtime
prepare name rt@(Runtime {loadedClasses = classLoadingInfo}) =
  let classLoaderInfo = classLoadingInfo Map.! (ClassId undefined undefined)
      (rt1, ref) = malloc rt
  in do
    rt2 <- writeStaticFields (ClassId undefined undefined) rt1 ref
    return rt2{loadedClasses = Map.insert (ClassId undefined undefined) classLoaderInfo classLoadingInfo}

writeStaticFields :: ClassId -> Runtime -> Ref -> Either VMError Runtime
writeStaticFields classId rt ref = let (s, h) = heap rt
                                       jobject = h ! ref
                                   in do
                                     sym <- getSymTable rt classId
                                     bc <- getByteCode rt classId
                                     let staticSearch fi = FieldStatic `elem` fieldAccessFlags fi
                                     bc $> body >>> fields >>> filter staticSearch >>> foldl (prepareStaticField sym ref) (return rt)


getDefaultValue :: Runtime -> String -> Either VMError JValue
getDefaultValue rt name = case parseFieldDescriptor name of
  Left err -> Left $ StateError rt SpecifyMeError
  Right d -> case fieldType d of
    BaseType t -> maybeToEither (StateError rt SpecifyMeError) $ Map.lookup t baseDefaultValues
    _ -> return nullReference

prepareStaticField :: SymTable -> Ref -> Either VMError Runtime -> FieldInfo -> Either VMError Runtime
prepareStaticField sym ref ert fi = do
  rt <- ert
  fieldName <- fieldNameIndex >>> getStringLiteral sym $ fi
  descriptorName <- getStringLiteral sym $ fieldDescriptorIndex fi
  defaultValue <- getDefaultValue rt descriptorName
  writeField rt ref (fieldName, defaultValue)
