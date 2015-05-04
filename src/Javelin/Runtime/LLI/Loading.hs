module Javelin.Runtime.LLI.Loading
where

import Javelin.ByteCode.Data
import Javelin.Runtime.Structures
import Javelin.Util
import Javelin.Runtime.LLI.ClassPath
import Javelin.Runtime.LLI.Resolving
import Javelin.ByteCode.ClassFile (parse)

import Control.Monad.Trans.Maybe
import Control.Monad (liftM)
import Data.Word (Word16)
import Data.Map.Lazy as Map (fromList, insert, lookup)
import Control.Applicative ((<$>))
import Data.ByteString.Lazy (ByteString, unpack)
import Javelin.Util
import Control.Arrow ((>>>))


-- §5.3 Creation and Loading
load :: ClassRequest -> Runtime -> IO (Either VMError Runtime)
load request@(ClassRequest _ name) rt =
  let classLoadFunction = if isArray name then loadArray else loadClass
  in classLoadFunction request rt

loadClass :: ClassLoadMethod
loadClass request@(ClassRequest BootstrapClassLoader _) rt = loadClassWithBootstrap request rt
loadClass request rt = loadClassWithUserDefCL request rt

isArray :: ClassName -> Bool
isArray name = head name == '['

type ClassLoadMethod = ClassRequest -> Runtime -> IO (Either VMError Runtime)

-- §5.3.1 Loading Using the Bootstrap Class Loader
loadClassWithBootstrap :: ClassRequest -> Runtime -> IO (Either VMError Runtime)
loadClassWithBootstrap request@(ClassRequest _ name) rt@(Runtime {classPathLayout = layout}) = 
  case getInitiatingClassLoader rt name of
    Just BootstrapClassLoader -> return $ Right rt
    _ -> do
      maybeBytes <- runMaybeT $ getClassBytes (getName request) layout
      let eitherBytes = maybeToEither (Linkage $ NoClassDefFoundClassNotFoundError ClassNotFoundException) maybeBytes
      return $ do
        bytes <- eitherBytes
        derive request rt BootstrapClassLoader bytes

-- §5.3.2 Loading Using a User-defined Class Loader
loadClassWithUserDefCL :: ClassLoadMethod
loadClassWithUserDefCL request rt = undefined

-- §5.3.3 Creating Array Classes
loadArray :: ClassLoadMethod
loadArray request rt = undefined

-- §5.3.4 Loading Constraints
-- not implemented yet

-- §5.3.5 Deriving a Class from a class File Representation
derive :: ClassRequest -> Runtime -> ClassLoader -> ByteString -> Either VMError Runtime
derive request@(ClassRequest initCL name) rt defCL bs = do
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
      symbolics = deriveSymTable pool
      thisIndex = this $ body bc
  in case Map.lookup (fromIntegral thisIndex) symbolics of
    Just (ClassOrInterface x) -> return symbolics
    _ -> linkageLeft $ InternalError CantCheckClassRepresentation

checkSuperClass :: ClassRequest -> ClassLoader -> ByteCode -> SymTable -> Runtime -> Either VMError Runtime
checkSuperClass request defCL bc sym rt =
  let superClassIdx = super $ body bc
      loadingClass = getName request
  in case (loadingClass, superClassIdx) of
    ("java.lang.Object", 0) -> Right rt
    ("java.lang.Object", _) -> linkageLeft $ InternalError ClassObjectHasNoSuperClasses
    (_, 0) -> linkageLeft $ InternalError OnlyClassObjectHasNoSuperClass
    (_, idx) -> case Map.lookup idx sym of
      Nothing -> undefined
      Just (ClassOrInterface parent) -> do
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
  case Map.lookup interfaceIdx sym of
    Nothing -> linkageLeft $ InternalError SymTableHasNoClassEntryAtIndex
    Just (ClassOrInterface parent) -> do
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
  


-- §5.1 The Runtime Constant Pool

deriveSymTable :: ConstantPool -> SymTable
deriveSymTable p = deriveReduce p (length p - 1) $ fromList []

deriveReduce :: ConstantPool -> Int -> SymTable -> SymTable
deriveReduce _ (-1) d = d
deriveReduce p i d = deriveReduce p (i - 1) d2
  where item = p !! i
        d2 = case deriveReference p item of
          Just ref -> insert (fromIntegral i) ref d
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
