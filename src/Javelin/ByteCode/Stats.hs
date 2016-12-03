{-# LANGUAGE BangPatterns #-}

module Javelin.ByteCode.Stats
where

import Javelin.ByteCode.ClassFile (parse)
import qualified Data.Map.Strict as Map
import Control.Monad
import System.Directory
import Data.Word (Word8)
import Data.Binary.Get
import Javelin.ByteCode.Data
import Data.Foldable
import Debug.Trace

import qualified Data.ByteString.Lazy as LBS (ByteString)
import qualified Data.ByteString as BS (unpack, readFile)

-- all instructions
-- pretty printing
-- error messages

stats :: FilePath -> IO String
stats path = do
  files <- getDirectoryContents path
  let filePaths = map (path ++) .filter (`notElem` [".", ".."]) $ files
  freqs <- calcFreqs mempty filePaths
  return $ show freqs

calcFreqs :: Map.Map String Integer -> [FilePath] -> IO (Either String (Map.Map String Integer))
calcFreqs accum [] = return $ Right accum
calcFreqs !accum (f:fs) = do
  parsed <- parseFileContents f
  case parsed of
    Left msg -> return $ Left msg
    Right bc -> calcFreqs (addFreq accum bc) fs

addFreq :: Map.Map OpCode Integer -> ByteCode -> Map.Map OpCode Integer
addFreq freq bc = let opCodes = do
                        method <- methods $ body bc
                        attr <- methodAttrs method
                        guard (isCodeAttr attr)
                        instruction <- code attr
                        return $ oc instruction
                  in composeFreqs freq opCodes

composeFreqs :: Map.Map OpCode Integer -> [OpCode] -> Map.Map OpCode Integer
composeFreqs x [] = x
composeFreqs x (c:cs) = composeFreqs (Map.alter statsAlter c x) cs
  where statsAlter = trace "cake" $ Just . maybe 1 (1 + )

isCodeAttr :: AttrInfo -> Bool
isCodeAttr (CodeAttr _ _ _ _ _) = True
isCodeAttr _ = False

readFileContents :: FilePath -> IO [Word8]
readFileContents path = print "reading" >> BS.unpack <$> BS.readFile path

parseFileContents :: FilePath -> IO (Either String ByteCode)
parseFileContents path = do
  contents <- readFileContents path
  print "parsing"
  let parsed = parse contents
  print "parsed"
  return $ either formatParseError validateParseResult parsed

formatParseError :: (LBS.ByteString, ByteOffset, String) -> Either String ByteCode
formatParseError (_, _, msg) = Left msg

validateParseResult :: (LBS.ByteString, ByteOffset, ByteCode) -> Either String ByteCode
validateParseResult (_, _, bc) = trace "validate" $ Right bc

type OpCode = String

oc :: Instruction -> String
oc Nop = "nop"
oc AConstNull = "aconst_null"
oc IConstM1 =  "iconst_m1"
oc IConst0 = "iconst_0"
oc IConst1 = "iconst_1"

oc _ = "unknown"


traverse' :: (Applicative m) => (a -> m b) -> [a] -> m [b]
traverse' _ [] = pure []
traverse' f (x:xs) = (:) <$> f x <*> traverse' f xs

ap :: Maybe (a -> b) -> Maybe a -> Maybe b
ap iof ioa = do
  f <- iof
  a <- ioa
  return $ f a

x :: IO [()]
x = mapM (\_ -> print "cake") [1..]
mapMExample = do
  list <- x
  print $ list !! 0

y :: IO [()]
y = sequence $ map (\_ -> print "cake") [1..]
sequenceExample = do
  list <- y
  print $ list !! 0

z :: [IO ()]
z = map (const $ print "cake") [1..]
mapExample = z !! 0
