module Javelin.Runtime.LLI.Loading
where

import Javelin.Runtime.LLI.ClassPath
import Javelin.Runtime.Structures
import Javelin.ByteCode.Data
import Javelin.Runtime.LLI.Resolving
import Javelin.ByteCode.ClassFile (parse)

import Data.Word (Word16)
import Data.Map as Map (insert, lookup)
import Data.ByteString.Lazy (ByteString, unpack)

import Control.Monad.Trans.Maybe




-- 5.1 Deriving the Run-Time Constant Pool

deriveUtf8 :: ConstantPool -> Word16 -> String
deriveUtf8 p idx = stringValue $ p !! fromIntegral idx
-- note: fix, value at index could be not Utf8Info, stringValue not applicable
-- or throw an exception: invalid bytecode

deriveSymTable :: ConstantPool -> SymTable
deriveSymTable p = map (deriveRef p) p

deriveRef :: ConstantPool -> Constant -> SymbolicReference
deriveRef p (ClassInfo idx) =
  ClassOrInterface $ deriveUtf8 p idx
deriveRef p (Fieldref classIdx nameAndTypeIdx) =
  FieldReference $ deriveFromClass classIdx nameAndTypeIdx p
deriveRef p (Methodref classIdx typeIdx) =
  ClassMethodReference $ deriveFromClass classIdx typeIdx p
deriveRef p (InterfaceMethodref classIdx typeIdx) =
  InterfaceMethodReference $ deriveFromClass classIdx typeIdx p
deriveRef p (MethodHandleInfo x y) = undefined
deriveRef p (MethodTypeInfo idx) =
  MethodTypeReference $ deriveUtf8 p idx
deriveRef p (InvokeDynamicInfo x y) = undefined
deriveRef p (StringInfo idx) =
  StringLiteral $ deriveUtf8 p idx
-- note: required is an additional method to add strings to symtable (due to intern)
deriveRef p (DoubleInfo val) =
  DoubleLiteral val
-- note: repr in IEEE 754 double point
deriveRef p (FloatInfo val) =
  FloatLiteral val
-- note: repr in IEEE 754 single point
deriveRef p (LongInfo val) =
  LongLiteral val
deriveRef p (IntegerInfo val) =
  IntegerLiteral val

deriveFromClass :: (Integral i) => i -> i -> ConstantPool -> PartReference
deriveFromClass classIdx nameAndTypeIdx p =
  let classInfo = p !! fromIntegral classIdx
      nameAndTypeInfo = p !! fromIntegral nameAndTypeIdx
      className = stringValue $ p !! fromIntegral (nameIndex classInfo)
      memberName = stringValue $ p !! fromIntegral (nameIndex nameAndTypeInfo)
      memberDescriptor = stringValue $ p !! fromIntegral (nameAndTypeDescriptorIndex nameAndTypeInfo)
  in PartReference className memberName memberDescriptor




-- 5.3.5 Deriving a Class from a class File Representation
deriveClass :: ClassRequest -> Runtime -> ClassLoader -> ByteString -> Either VMError Runtime
deriveClass request@(ClassRequest initCL name) rt defCL bs = do
  checkInitiatingClassLoader initCL name rt
  bc <- checkClassFileFormat bs rt
  checkClassVersion bc
  syms <- checkRepresentedClass name rt bc
  checkSuperClass request defCL bc syms rt
    >>= checkSuperInterfaces request defCL bc syms
    >>= recordClassLoading name bc syms initCL defCL

checkInitiatingClassLoader :: ClassLoader -> ClassName -> Runtime -> Either VMError Runtime
checkInitiatingClassLoader initCL name rt = do
  let actualInitCl = getInitiatingClassLoader rt name
  if Just initCL == actualInitCl
    then linkageLeft LinkageError
    else Right rt

checkClassFileFormat :: ByteString -> Runtime -> Either VMError ByteCode
checkClassFileFormat bs rt = let body = parse $ unpack bs in
  case body of
    Left (_, _, msg) -> linkageLeft ClassFormatError
    Right (_, _, byteCode) -> Right byteCode
    
checkClassVersion :: ByteCode -> Either VMError ()
checkClassVersion bc = if minVer bc < 0 || majVer bc > 1050
                       then linkageLeft UnsupportedClassVersionError
                       else Right ()

checkRepresentedClass :: ClassName -> Runtime -> ByteCode -> Either VMError SymTable
checkRepresentedClass name rt bc =
  let pool = constPool $ body bc
      symTable = deriveSymTable pool
      thisIndex = this $ body bc
  in case symTable !! (fromIntegral thisIndex) of
    (ClassOrInterface x) -> return symTable
    _ -> linkageLeft $ InternalError CantCheckClassRepresentation

checkSuperClass :: ClassRequest -> ClassLoader -> ByteCode -> SymTable -> Runtime -> Either VMError Runtime
checkSuperClass request defCL bc sym rt =
  let superClassIdx = super $ body bc
      loadingClass = getName request
  in case (loadingClass, superClassIdx) of
    ("java.lang.Object", 0) -> Right rt
    ("java.lang.Object", _) -> linkageLeft $ InternalError ClassObjectHasNoSuperClasses
    (_, 0) -> linkageLeft $ InternalError OnlyClassObjectHasNoSuperClass
    (_, idx) -> case sym !! fromIntegral idx of
      (ClassOrInterface parent) -> do
        rt <- resolve (ClassRequest defCL parent) rt
        case isInterface parent rt of
          Nothing -> linkageLeft $ InternalError CouldNotFindAccessFlags
          Just True -> linkageLeft IncompatibleClassChangeError
          Just False -> let thisAccessFlags = classAccessFlags $ body $ bc
                            thisIsInterface = elem ClassInterface thisAccessFlags
                        in case (thisIsInterface, parent) of
                          (True, "java.lang.Object") -> Right rt
                          (True, _) -> linkageLeft $ InternalError InterfaceMustHaveObjectAsSuperClass
                          (False, parent) -> if parent == getName request
                                             then linkageLeft ClassCircularityError
                                             else Right rt


checkSuperInterfaces :: ClassRequest -> ClassLoader -> ByteCode -> SymTable -> Runtime -> Either VMError Runtime
checkSuperInterfaces request defCL bc syms rt = let superInterfaces = interfaces $ body bc
                                                in foldl (checkSuperInterface request defCL bc syms) (Right rt) superInterfaces
checkSuperInterface :: ClassRequest -> ClassLoader -> ByteCode -> SymTable -> Either VMError Runtime -> Word16 -> Either VMError Runtime
checkSuperInterface request defCL bc sym eitherRt interfaceIdx = do
  rt <- eitherRt
  let loadingClass = getName request
  case sym !! fromIntegral interfaceIdx of
    (ClassOrInterface parent) -> do
      rt <- resolve (ClassRequest defCL parent) rt
      case isInterface parent rt of
        Nothing -> linkageLeft $ InternalError CouldNotFindAccessFlags
        Just True -> if parent == loadingClass
                     then linkageLeft ClassCircularityError
                     else Right rt
        Just False -> linkageLeft $ IncompatibleClassChangeError


recordClassLoading :: ClassName -> ByteCode -> SymTable -> ClassLoader -> ClassLoader -> Runtime -> Either VMError Runtime
recordClassLoading name bc sym defCL initCL
  rt@(Runtime {classLoading = cls, symbolics = syms, bytecodes = bcs}) =
    let clInfo = ClassLoaderInfo defCL initCL (name, defCL) Loaded False Nothing
    in Right $ rt {classLoading = insert name clInfo cls,
                   symbolics = insert name sym syms,
                   bytecodes = insert name bc bcs}



-- 5.3 Creation and Loading top level code
load :: ClassRequest -> Runtime -> IO (Either VMError Runtime)
load request@(ClassRequest _ name) rt =
  (if isArray name then loadArray else loadClass) request rt

loadClass :: ClassLoadMethod
loadClass request@(ClassRequest BootstrapClassLoader _) rt = loadClassWithBootstrap request rt
loadClass request rt = loadClassWithUserDefCL request rt

isArray :: ClassName -> Bool
isArray name = head name == '['

type ClassLoadMethod = ClassRequest -> Runtime -> IO (Either VMError Runtime)

-- 5.3.1 Loading Using the Bootstrap Class Loader
loadClassWithBootstrap :: ClassRequest -> Runtime -> IO (Either VMError Runtime)
loadClassWithBootstrap request@(ClassRequest _ name) rt@(Runtime {classPathLayout = layout}) = 
  case getInitiatingClassLoader rt name of
    Just BootstrapClassLoader -> return $ Right rt
    _ -> do
      maybeBytes <- runMaybeT $ getClassBytes name layout
      let eitherBytes = maybeToEither (Linkage $ NoClassDefFoundClassNotFoundError ClassNotFoundException) maybeBytes
      return $ do
        bytes <- eitherBytes
        deriveClass request rt BootstrapClassLoader bytes

-- 5.3.2 Loading Using a User-defined Class Loader
loadClassWithUserDefCL :: ClassLoadMethod
loadClassWithUserDefCL request rt = undefined

-- 5.3.3 Creating Array Classes
loadArray :: ClassLoadMethod
loadArray request rt = undefined

-- 5.3.4 Loading Constraints
-- not implemented yet


