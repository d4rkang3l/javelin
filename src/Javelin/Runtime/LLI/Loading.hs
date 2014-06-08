module Javelin.Runtime.LLI.Loading
where

import Javelin.ByteCode.Data
import Javelin.Runtime.Structures
import Javelin.Util
import Javelin.Runtime.LLI.ClassPath

import Data.Word (Word16)
import Data.Map.Lazy as Map (fromList, insert, lookup)
import Control.Applicative ((<$>))




-- Loading

load :: Maybe ClassName -> ClassName -> Runtime -> Either String Runtime
load trigger name rt =
  let classLoadFunction = if isArray name then loadArray else loadClass
      properClassLoader = getProperClassLoader trigger rt
  in case properClassLoader of
          Nothing -> Left "Some error to be specified"
          Just cl -> classLoadFunction name rt cl

getProperClassLoader :: Maybe ClassName -> Runtime -> Maybe ClassLoader
getProperClassLoader Nothing (Runtime {classLoaders = loaders}) = loaders !? 0
getProperClassLoader (Just trigger)
  rt@(Runtime {classLoading = classLoading, classLoaders = classLoaders}) =
  do
    classLoadingInfo <- Map.lookup trigger classLoading
    let definingCLIndex = defining classLoadingInfo
    classLoaders !? definingCLIndex

type ClassLoadMethod = ClassName -> Runtime -> ClassLoader -> Either String Runtime
loadArray :: ClassLoadMethod
loadArray name rt classLoader = undefined
loadClass :: ClassLoadMethod
loadClass name rt (UserDefinedClassLoader cl) = undefined
loadClass name rt cl@BootstrapClassLoader =
  case getInitiatingClassLoader name rt of
    Nothing -> loadClassWithBootstrap name rt
    Just initCl -> if initCl == cl
                   then Right rt
                   else loadClassWithBootstrap name rt

loadClassWithBootstrap :: ClassName -> Runtime -> Either String Runtime
loadClassWithBootstrap name rt@(Runtime {layout = layout}) =
  let bytes = getClassBytes name layout
  in undefined
  


isArray :: ClassName -> Bool
isArray name = undefined






-- Derivation

derivePool :: ConstantPool -> DerivedPool
derivePool p = deriveReduce p (length p - 1) $ fromList []

deriveReduce :: ConstantPool -> Int -> DerivedPool -> DerivedPool
deriveReduce _ (-1) d = d
deriveReduce p i d = deriveReduce p (i - 1) d2
  where item = p !! i
        d2 = case deriveReference p item of
          Just ref -> insert i ref d
          Nothing -> d

deriveReference :: ConstantPool -> Constant -> Maybe SymbolicReference
deriveReference p c = case c of
  ClassInfo idx ->
    ClassOrInterface <$> deriveUtf8 p idx
  Fieldref classIdx typeIdx ->
    FieldReference <$> deriveFromClass classIdx typeIdx p
  Methodref classIdx typeIdx ->
    ClassMethodReference <$> deriveFromClass classIdx typeIdx p
  InterfaceMethodref classIdx typeIdx ->
    InterfaceMethodReference <$> deriveFromClass classIdx typeIdx p
  MethodHandleInfo x y -> undefined
  MethodTypeInfo idx -> MethodTypeReference <$> deriveUtf8 p idx
  InvokeDynamicInfo x y -> undefined
  StringInfo idx -> StringLiteral <$> deriveUtf8 p idx
  DoubleInfo val -> Just $ DoubleLiteral val
  FloatInfo val -> Just $ FloatLiteral val
  LongInfo val -> Just $ LongLiteral val
  IntegerInfo val -> Just $ IntegerLiteral val
  _ -> Nothing



-- Derivation utility functions

deriveFromClass :: (Integral i) => i -> i -> ConstantPool -> Maybe PartReference
deriveFromClass classIdx typeIdx p = do
  classInfo <- p !? classIdx
  nameAndTypeInfo <- p !? typeIdx
  case (classInfo, nameAndTypeInfo) of
    (ClassInfo classNameIdx, NameAndTypeInfo methodNameIdx descriptorIdx) -> do
      className <- p !? classNameIdx
      methodName <- p !? methodNameIdx
      descriptor <- p!? descriptorIdx
      case (className, methodName, descriptor) of
        (Utf8Info a, Utf8Info b, Utf8Info c) -> return $ PartReference a b c
        _ -> Nothing
    _ -> Nothing

deriveUtf8 :: ConstantPool -> Word16 -> Maybe String
deriveUtf8 p idx = do
  name <- p !? idx
  case name of
    Utf8Info name -> Just name
    _ -> Nothing
    


