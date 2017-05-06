module Javelin.Util

where
import Control.Monad.Trans.Maybe

(!?) :: (Integral i) => [a] -> i -> Maybe a
(!?) list index = let indexInt = fromIntegral index in
  if length list <= indexInt
  then Nothing
  else Just $ list !! indexInt

-- These are some missing Haskell functions, need to move somewhere else
toMaybeT :: (Monad m) => Maybe a -> MaybeT m a
toMaybeT = MaybeT . return


cake :: String -> Integer
cake x = 42

-- Srsly, Haskell, where is my 'replace' function?
replace :: Char -> Char -> String -> String
replace co cr = map (\c -> if c == co then cr else c)

infix 0 $>
($>) :: a -> (a -> b) -> b
($>) x f = f x

at :: Integral b => [a] -> b -> a
at cc i = cc !! ((fromIntegral i) - 1)
