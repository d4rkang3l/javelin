module Javelin.ByteCode.ConstantPool (getConstants)
where

import Data.Word (Word32, Word16, Word8)
import Data.Map.Lazy (findWithDefault, fromList, Map)
import Control.Applicative
import Data.Binary.Get
import Unsafe.Coerce

import Javelin.ByteCode.Data
import Javelin.ByteCode.Utils


getConstants 1 = return []
getConstants len = do
  constant <- getConstant
  let double = ([constant, constant] ++) <$> (getConstants $ len - 2)
      single = (constant :) <$> (getConstants $ len - 1)
  case constant of
    LongInfo _ -> double
    DoubleInfo _ -> double
    otherwise -> single

getConstant :: Get Constant
getConstant = do
  tag <- getWord8
  findWithDefault (failingConstParser tag) tag constantTypeParser

failingConstParser :: Word8 -> Get Constant
failingConstParser x = fail $ "Undefined constant with index " ++ show x ++ "\n"

constantTypeParser :: Map Word8 (Get Constant)
constantTypeParser = fromList [(1, utf8InfoParser), (3, integerInfoParser),
                               (4, floatInfoParser), (5, longInfoParser),
                               (6, doubleInfoParser), (7, classInfoParser),
                               (8, stringInfoParser), (9, fieldrefParser),
                               (10, methodrefParser), (11, interfaceMethodrefParser),
                               (12, nameAndTypeInfoParser), (15, methodHandleInfoParser),
                               (16, methodTypeInfoParser), (18, invokeDynamicInfoParser)]

utf8InfoParser :: Get Constant
utf8InfoParser = do
  byteStringLen <- getWord16
  byteString <- getByteString $ fromIntegral byteStringLen
  return $ Utf8Info $ bytesToString byteString

twoTwoBytesInfoParser :: (Word16 -> Word16 -> Constant) -> Get Constant
twoTwoBytesInfoParser constConstr = constConstr <$> getWord16 <*> getWord16
twoFourBytesInfoParser :: (Word32 -> Word32 -> Constant) -> Get Constant
twoFourBytesInfoParser constConstr = constConstr <$> getWord32 <*> getWord32

twoBytesInfoParser :: (Word16 -> Constant) -> Get Constant
twoBytesInfoParser constConstr = constConstr <$> getWord16
fourBytesInfoParser :: (Word32 -> Constant) -> Get Constant
fourBytesInfoParser constConstr = constConstr <$> getWord32

fieldrefParser = twoTwoBytesInfoParser Fieldref
methodrefParser = Methodref <$> getWord16 <*> getWord16

interfaceMethodrefParser = twoTwoBytesInfoParser InterfaceMethodref
nameAndTypeInfoParser = twoTwoBytesInfoParser NameAndTypeInfo
classInfoParser = twoBytesInfoParser ClassInfo
stringInfoParser = twoBytesInfoParser StringInfo

integerInfoParser = IntegerInfo <$> unsafeCoerce <$> getWord32
floatInfoParser = FloatInfo <$> unsafeCoerce <$> getWord32
longInfoParser = LongInfo <$> unsafeCoerce <$> getWord64
doubleInfoParser = DoubleInfo <$> unsafeCoerce <$> getWord64

methodHandleInfoParser = MethodHandleInfo <$> getWord8 <*> getWord16
methodTypeInfoParser = MethodTypeInfo <$> getWord16
invokeDynamicInfoParser = twoTwoBytesInfoParser InvokeDynamicInfo
