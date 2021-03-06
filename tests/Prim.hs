--
-- QuickCheck tests for Megaparsec's primitive parser combinators.
--
-- Copyright © 2015–2016 Megaparsec contributors
--
-- Redistribution and use in source and binary forms, with or without
-- modification, are permitted provided that the following conditions are
-- met:
--
-- * Redistributions of source code must retain the above copyright notice,
--   this list of conditions and the following disclaimer.
--
-- * Redistributions in binary form must reproduce the above copyright
--   notice, this list of conditions and the following disclaimer in the
--   documentation and/or other materials provided with the distribution.
--
-- THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS “AS IS” AND ANY
-- EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
-- WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
-- DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS BE LIABLE FOR ANY
-- DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
-- DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
-- OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
-- HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
-- STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
-- ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
-- POSSIBILITY OF SUCH DAMAGE.

{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE Rank2Types        #-}
{-# LANGUAGE RecordWildCards   #-}
{-# LANGUAGE TypeFamilies      #-}
{-# OPTIONS -fno-warn-orphans  #-}

module Prim (tests) where

import Control.Applicative
import Control.Monad.Cont
import Control.Monad.Except
import Control.Monad.Identity
import Control.Monad.Reader
import Data.Char (isLetter, toUpper, chr)
import Data.Foldable (asum)
import Data.List (isPrefixOf, foldl')
import Data.List.NonEmpty (NonEmpty (..))
import Data.Maybe (maybeToList, fromMaybe)
import Data.Proxy
import Data.Set (Set)
import Data.Word (Word8)
import Prelude hiding (span)
import qualified Control.Monad.State.Lazy    as L
import qualified Control.Monad.State.Strict  as S
import qualified Control.Monad.Writer.Lazy   as L
import qualified Control.Monad.Writer.Strict as S
import qualified Data.ByteString.Char8       as B
import qualified Data.ByteString.Lazy.Char8  as BL
import qualified Data.List.NonEmpty          as NE
import qualified Data.Set                    as E
import qualified Data.Text                   as T
import qualified Data.Text.Lazy              as TL

import Test.Framework
import Test.Framework.Providers.HUnit (testCase)
import Test.Framework.Providers.QuickCheck2 (testProperty)
import Test.QuickCheck hiding (label)
import Test.HUnit (Assertion)

import Text.Megaparsec.Char
import Text.Megaparsec.Combinator
import Text.Megaparsec.Error
import Text.Megaparsec.Pos
import Text.Megaparsec.Prim
import Text.Megaparsec.String

import Pos ()
import Error ()
import Util

tests :: Test
tests = testGroup "Primitive parser combinators"
  [ testProperty "Stream lazy byte string"             prop_byteStringL
  , testProperty "Stream lazy byte string (pos)"       prop_byteStringL_pos
  , testProperty "Stream strict byte string"           prop_byteStringS
  , testProperty "Stream strict byte string (pos)"     prop_byteStringS_pos
  , testProperty "Stream lazy text"                    prop_textL
  , testProperty "Stream lazy text (pos)"              prop_textL_pos
  , testProperty "Stream strict text"                  prop_textS
  , testProperty "Stream strict text (pos)"            prop_textS_pos
  , testProperty "position in custom stream, eof"      prop_cst_eof
  , testProperty "position in custom stream, token"    prop_cst_token
  , testProperty "position in custom stream, tokens"   prop_cst_tokens
  , testProperty "ParsecT functor"                     prop_functor
  , testProperty "ParsecT applicative (<*>)"           prop_applicative_0
  , testProperty "ParsecT applicative (<*>) meok-cerr" prop_applicative_1
  , testProperty "ParsecT applicative (*>)"            prop_applicative_2
  , testProperty "ParsecT applicative (<*)"            prop_applicative_3
  , testProperty "ParsecT alternative empty and (<|>)" prop_alternative_0
  , testProperty "ParsecT alternative (<|>)"           prop_alternative_1
  , testProperty "ParsecT alternative (<|>) pos"       prop_alternative_2
  , testProperty "ParsecT alternative (<|>) hints"     prop_alternative_3
  , testProperty "ParsecT alternative many"            prop_alternative_4
  , testProperty "ParsecT alternative some"            prop_alternative_5
  , testProperty "ParsecT alternative optional"        prop_alternative_6
  , testProperty "ParsecT monad return"                prop_monad_0
  , testProperty "ParsecT monad (>>)"                  prop_monad_1
  , testProperty "ParsecT monad (>>=)"                 prop_monad_2
  , testProperty "ParsecT monad fail"                  prop_monad_3
  , testProperty "ParsecT monad laws: left identity"   prop_monad_left_id
  , testProperty "ParsecT monad laws: right identity"  prop_monad_right_id
  , testProperty "ParsecT monad laws: associativity"   prop_monad_assoc
  , testProperty "ParsecT monad io (liftIO)"           prop_monad_io
  , testProperty "ParsecT monad reader ask"   prop_monad_reader_ask
  , testProperty "ParsecT monad reader local" prop_monad_reader_local
  , testProperty "ParsecT monad state get"    prop_monad_state_get
  , testProperty "ParsecT monad state put"    prop_monad_state_put
  , testProperty "ParsecT monad cont"         prop_monad_cont
  , testProperty "ParsecT monad error: throw" prop_monad_error_throw
  , testProperty "ParsecT monad error: catch" prop_monad_error_catch
  , testProperty "combinator unexpected"      prop_unexpected
  , testProperty "combinator failure"                  prop_failure
  , testProperty "combinator label"                    prop_label
  , testProperty "combinator hidden hints"             prop_hidden_0
  , testProperty "combinator hidden error"             prop_hidden_1
  , testProperty "combinator try"                      prop_try
  , testProperty "combinator lookAhead"                prop_lookAhead_0
  , testProperty "combinator lookAhead hints"          prop_lookAhead_1
  , testProperty "combinator lookAhead messages"       prop_lookAhead_2
  , testCase     "combinator lookAhead cerr"           case_lookAhead_3
  , testProperty "combinator notFollowedBy"       prop_notFollowedBy_0
  , testProperty "combinator notFollowedBy twice" prop_notFollowedBy_1
  , testProperty "combinator notFollowedBy eof"   prop_notFollowedBy_2
  , testCase     "combinator notFollowedBy cerr"  case_notFollowedBy_3a
  , testCase     "combinator notFollowedBy cerr"  case_notFollowedBy_3b
  , testCase     "combinator notFollowedBy eerr"  case_notFollowedBy_4a
  , testCase     "combinator notFollowedBy eerr"  case_notFollowedBy_4b
  , testProperty "combinator withRecovery"             prop_withRecovery_0
  , testCase     "combinator withRecovery eok"         case_withRecovery_1
  , testCase     "combinator withRecovery meerr-rcerr" case_withRecovery_2
  , testCase     "combinator withRecovery meerr-reok"  case_withRecovery_3a
  , testCase     "combinator withRecovery meerr-reok"  case_withRecovery_3b
  , testCase     "combinator withRecovery mcerr-rcok"  case_withRecovery_4a
  , testCase     "combinator withRecovery mcerr-rcok"  case_withRecovery_4b
  , testCase     "combinator withRecovery mcerr-rcerr" case_withRecovery_5
  , testCase     "combinator withRecovery mcerr-reok"  case_withRecovery_6a
  , testCase     "combinator withRecovery mcerr-reok"  case_withRecovery_6b
  , testCase     "combinator withRecovery mcerr-reerr" case_withRecovery_7
  , testCase     "combinator eof return value"    case_eof
  , testProperty "combinator token"                    prop_token
  , testProperty "combinator tokens"                   prop_tokens_0
  , testProperty "combinator tokens (consumption)"     prop_tokens_1
  , testProperty "parser state position"               prop_state_pos
  , testProperty "parser state position (push)"        prop_state_pushPosition
  , testProperty "parser state position (pop)"         prop_state_popPosition
  , testProperty "parser state input"                  prop_state_input
  , testProperty "parser state tab width"              prop_state_tab
  , testProperty "parser state general"                prop_state
  , testProperty "parseMaybe"                          prop_parseMaybe
  , testProperty "custom state parsing"                prop_runParser'
  , testProperty "custom state parsing (transformer)"  prop_runParserT'
  , testProperty "state on failure (mplus)"         prop_stOnFail_0
  , testProperty "state on failure (tab)"           prop_stOnFail_1
  , testProperty "state on failure (eof)"           prop_stOnFail_2
  , testProperty "state on failure (notFollowedBy)" prop_stOnFail_3
  , testProperty "ReaderT try"              prop_ReaderT_try
  , testProperty "ReaderT notFollowedBy"    prop_ReaderT_notFollowedBy
  , testProperty "StateT alternative (<|>)" prop_StateT_alternative
  , testProperty "StateT lookAhead"         prop_StateT_lookAhead
  , testProperty "StateT notFollowedBy"     prop_StateT_notFollowedBy
  , testProperty "WriterT"                  prop_WriterT ]

instance Arbitrary a => Arbitrary (State a) where
  arbitrary = State
    <$> arbitrary
    <*> arbitrary
    <*> (unsafePos <$> choose (1, 20))

-- Various instances of Stream

prop_byteStringL :: Word8 -> NonNegative Int -> Property
prop_byteStringL ch' n = parse p "" (BL.pack s) === Right s
  where p  = many (char ch) :: Parsec Dec BL.ByteString String
        s  = replicate (getNonNegative n) ch
        ch = byteToChar ch'

prop_byteStringL_pos :: Pos -> SourcePos -> Char -> Property
prop_byteStringL_pos w pos ch =
  updatePos (Proxy :: Proxy String) w pos ch ===
  updatePos (Proxy :: Proxy BL.ByteString) w pos ch

prop_byteStringS :: Word8 -> NonNegative Int -> Property
prop_byteStringS ch' n = parse p "" (B.pack s) === Right s
  where p  = many (char ch) :: Parsec Dec B.ByteString String
        s  = replicate (getNonNegative n) ch
        ch = byteToChar ch'

prop_byteStringS_pos :: Pos -> SourcePos -> Char -> Property
prop_byteStringS_pos w pos ch =
  updatePos (Proxy :: Proxy String) w pos ch ===
  updatePos (Proxy :: Proxy B.ByteString) w pos ch

byteToChar :: Word8 -> Char
byteToChar = chr . fromIntegral

prop_textL :: Char -> NonNegative Int -> Property
prop_textL ch n = parse p "" (TL.pack s) === Right s
  where p = many (char ch) :: Parsec Dec TL.Text String
        s = replicate (getNonNegative n) ch

prop_textL_pos :: Pos -> SourcePos -> Char -> Property
prop_textL_pos w pos ch =
  updatePos (Proxy :: Proxy String) w pos ch ===
  updatePos (Proxy :: Proxy TL.Text) w pos ch

prop_textS :: Char -> NonNegative Int -> Property
prop_textS ch n = parse p "" (T.pack s) === Right s
  where p = many (char ch) :: Parsec Dec T.Text String
        s = replicate (getNonNegative n) ch

prop_textS_pos :: Pos -> SourcePos -> Char -> Property
prop_textS_pos w pos ch =
  updatePos (Proxy :: Proxy String) w pos ch ===
  updatePos (Proxy :: Proxy T.Text) w pos ch

-- Custom stream of tokens and position advancing

-- | This data type will represent tokens in input stream for the purposes
-- of next several tests.

data Span = Span
  { spanStart :: SourcePos
  , spanEnd   :: SourcePos
  , spanBody  :: NonEmpty Char
  } deriving (Eq, Ord, Show)

instance Stream [Span] where
  type Token [Span] = Span
  uncons [] = Nothing
  uncons (t:ts) = Just (t, ts)
  updatePos _ _ _ (Span start end _) = (start, end)

instance Arbitrary Span where
  arbitrary = do
    start <- arbitrary
    end   <- arbitrary `suchThat` (> start)
    Span start end <$> arbitrary

type CustomParser = Parsec Dec [Span]

prop_cst_eof :: State [Span] -> Property
prop_cst_eof st =
  (not . null . stateInput) st ==> (runParser' p st === r)
  where
    p = eof :: CustomParser ()
    h = head (stateInput st)
    apos = let (_:|z) = statePos st in spanStart h :| z
    r = (st { statePos = apos }, Left ParseError
      { errorPos        = apos
      , errorUnexpected = E.singleton (Tokens (nes h))
      , errorExpected   = E.singleton EndOfInput
      , errorCustom     = E.empty })

prop_cst_token :: State [Span] -> Span -> Property
prop_cst_token st@State {..} span = runParser' p st === r
  where
    p = pSpan span
    h = head stateInput
    (apos, npos) =
      let z = NE.tail statePos
      in (spanStart h :| z, spanEnd h :| z)
    r | null stateInput =
        ( st
        , Left ParseError
          { errorPos        = statePos
          , errorUnexpected = E.singleton EndOfInput
          , errorExpected   = E.singleton (Tokens $ nes span)
          , errorCustom     = E.empty } )
      | spanBody h == spanBody span =
          ( st { statePos = npos
               , stateInput = tail stateInput }
          , Right span )
      | otherwise =
          ( st { statePos = apos }
          , Left ParseError
            { errorPos        = apos
            , errorUnexpected = E.singleton (Tokens $ nes h)
            , errorExpected   = E.singleton (Tokens $ nes span)
            , errorCustom     = E.empty } )

pSpan :: Span -> CustomParser Span
pSpan span = token testToken (Just span)
  where
    f = E.singleton . Tokens . nes
    testToken x =
      if spanBody x == spanBody span
        then Right span
        else Left (f x, f span , E.empty)

prop_cst_tokens :: State [Span] -> [Span] -> Property
prop_cst_tokens st' ts =
  forAll (incCoincidence st' ts) $ \st@State {..} ->
  let
    p = tokens compareTokens ts :: CustomParser [Span]
    compareTokens x y = spanBody x == spanBody y
    updatePos' = updatePos (Proxy :: Proxy [Span]) stateTabWidth
    ts' = NE.fromList ts
    il = length . takeWhile id $ zipWith compareTokens stateInput ts
    tl = length ts
    consumed = take il stateInput
    (apos, npos) =
      let (pos:|z) = statePos
      in ( spanStart (head stateInput) :| z
         , foldl' (\q t -> snd (updatePos' q t)) pos consumed :| z )
    r | null ts = (st, Right [])
      | null stateInput =
        ( st
        , Left ParseError
          { errorPos        = statePos
          , errorUnexpected = E.singleton EndOfInput
          , errorExpected   = E.singleton (Tokens ts')
          , errorCustom     = E.empty } )
      | il == tl =
        ( st { statePos   = npos
             , stateInput = drop (length ts) stateInput }
        , Right consumed )
      | otherwise =
        ( st { statePos = apos }
        , Left ParseError
          { errorPos        = apos
          , errorUnexpected = E.singleton
            (Tokens . NE.fromList $ take (il + 1) stateInput)
          , errorExpected   = E.singleton (Tokens ts')
          , errorCustom     = E.empty } )
  in runParser' p st === r

incCoincidence :: State [Span] -> [Span] -> Gen (State [Span])
incCoincidence st ts = do
  n <- getSmall <$> arbitrary
  let (pre, post) = splitAt n (stateInput st)
      pre' = zipWith (\x t -> x { spanBody = spanBody t }) pre ts
  return st { stateInput = pre' ++ post }

-- Functor instance

prop_functor :: Integer -> Integer -> Property
prop_functor n m =
  ((+ m) <$> return n) /=\ n + m .&&. ((* n) <$> return m) /=\ n * m

-- Applicative instance

prop_applicative_0 :: Integer -> Integer -> Property
prop_applicative_0 n m = ((+) <$> pure n <*> pure m) /=\ n + m

prop_applicative_1 :: Char -> Char -> Property
prop_applicative_1 a b = a /= b ==> checkParser p r s
  where
    p = pure toUpper <*> (char a >> char a)
    r = posErr 1 s [utok b, etok a]
    s = [a,b]

prop_applicative_2 :: Integer -> Integer -> Property
prop_applicative_2 n m = (pure n *> pure m) /=\ m

prop_applicative_3 :: Integer -> Integer -> Property
prop_applicative_3 n m = (pure n <* pure m) /=\ n

-- Alternative instance

prop_alternative_0 :: Integer -> Property
prop_alternative_0 n = (empty <|> return n) /=\ n

prop_alternative_1 :: String -> String -> Property
prop_alternative_1 s0 s1
  | s0 == s1 = checkParser p (Right s0) s1
  | null s0  = checkParser p (posErr 0 s1 [utok (head s1), eeof]) s1
  | s0 `isPrefixOf` s1 =
      checkParser p (posErr s0l s1 [utok (s1 !! s0l), eeof]) s1
  | otherwise = checkParser p (Right s0) s0 .&&. checkParser p (Right s1) s1
    where p   = string s0 <|> string s1
          s0l = length s0

prop_alternative_2 :: Char -> Char -> Char -> Bool -> Property
prop_alternative_2 a b c l = checkParser p r s
  where p = char a <|> (char b >> char a)
        r | l         = Right a
          | a == b    = posErr 1 s [utok c, eeof]
          | a == c    = Right a
          | otherwise = posErr 1 s [utok c, etok a]
        s = if l then [a] else [b,c]

prop_alternative_3 :: Property
prop_alternative_3 = checkParser p r s
  where p  = asum [empty, string ">>>", empty, return "foo"] <?> "bar"
        p' = bsum [empty, string ">>>", empty, return "foo"] <?> "bar"
        bsum = foldl (<|>) empty
        r = simpleParse p' s
        s = ">>"

prop_alternative_4 :: NonNegative Int -> NonNegative Int
                   -> NonNegative Int -> Property
prop_alternative_4 a' b' c' = checkParser p r s
  where [a,b,c] = getNonNegative <$> [a',b',c']
        p = (++) <$> many (char 'a') <*> many (char 'b')
        r | null s = Right s
          | c > 0  = posErr (a + b) s $ [utok 'c', etok 'b', eeof]
                     ++ [etok 'a' | b == 0]
          | otherwise = Right s
        s = abcRow a b c

prop_alternative_5 :: NonNegative Int -> NonNegative Int
                   -> NonNegative Int -> Property
prop_alternative_5 a' b' c' = checkParser p r s
  where [a,b,c] = getNonNegative <$> [a',b',c']
        p = (++) <$> some (char 'a') <*> some (char 'b')
        r | null s = posErr 0 s [ueof, etok 'a']
          | a == 0 = posErr 0 s [utok (head s), etok 'a']
          | b == 0 = posErr a s $ [etok 'a', etok 'b'] ++
                     if c > 0 then [utok 'c'] else [ueof]
          | c > 0 = posErr (a + b) s [utok 'c', etok 'b', eeof]
          | otherwise = Right s
        s = abcRow a b c

prop_alternative_6 :: Bool -> Bool -> Bool -> Property
prop_alternative_6 a b c = checkParser p r s
  where p = f <$> optional (char 'a') <*> optional (char 'b')
        f x y = maybe "" (:[]) x ++ maybe "" (:[]) y
        r | c = posErr ab s $ [utok 'c', eeof] ++
                [etok 'a' | not a && not b] ++ [etok 'b' | not b]
          | otherwise = Right s
        s = abcRow a b c
        ab = fromEnum a + fromEnum b

-- Monad instance

prop_monad_0 :: Integer -> Property
prop_monad_0 n = checkParser (return n) (Right n) ""

prop_monad_1 :: Char -> Char -> Maybe Char -> Property
prop_monad_1 a b c = checkParser p r s
  where p = char a >> char b
        r = simpleParse (char a *> char b) s
        s = a : b : maybeToList c

prop_monad_2 :: Char -> Char -> Maybe Char -> Property
prop_monad_2 a b c = checkParser p r s
  where p = char a >>= \x -> char b >> return x
        r = simpleParse (char a <* char b) s
        s = a : b : maybeToList c

prop_monad_3 :: String -> Property
prop_monad_3 msg = checkParser p r s
  where p = fail msg :: Parser ()
        r = posErr 0 s [cstm (DecFail msg)]
        s = ""

prop_monad_left_id :: Integer -> Integer -> Property
prop_monad_left_id a b = (return a >>= f) !=! f a
  where f x = return $ x + b

prop_monad_right_id :: Integer -> Property
prop_monad_right_id a = (m >>= return) !=! m
  where m = return a

prop_monad_assoc :: Integer -> Integer -> Integer -> Property
prop_monad_assoc a b c = ((m >>= f) >>= g) !=! (m >>= (\x -> f x >>= g))
  where m = return a
        f x = return $ x + b
        g x = return $ x + c

-- MonadIO instance

prop_monad_io :: Integer -> Property
prop_monad_io n = ioProperty (liftM (=== Right n) (runParserT p "" ""))
  where p = liftIO (return n) :: ParsecT Dec String IO Integer

-- MonadReader instance

prop_monad_reader_ask :: Integer -> Property
prop_monad_reader_ask a = runReader (runParserT p "" "") a === Right a
  where p = ask :: ParsecT Dec String (Reader Integer) Integer

prop_monad_reader_local :: Integer -> Integer -> Property
prop_monad_reader_local a b =
  runReader (runParserT p "" "") a === Right (a + b)
  where p = local (+ b) ask :: ParsecT Dec String (Reader Integer) Integer

-- MonadState instance

prop_monad_state_get :: Integer -> Property
prop_monad_state_get a = L.evalState (runParserT p "" "") a === Right a
  where p = L.get :: ParsecT Dec String (L.State Integer) Integer

prop_monad_state_put :: Integer -> Integer -> Property
prop_monad_state_put a b = L.execState (runParserT p "" "") a === b
  where p = L.put b :: ParsecT Dec String (L.State Integer) ()

-- MonadCont instance

prop_monad_cont :: Integer -> Integer -> Property
prop_monad_cont a b = runCont (runParserT p "" "") id === Right (max a b)
  where p :: ParsecT Dec String
             (Cont (Either (ParseError Char Dec) Integer)) Integer
        p = do x <- callCC $ \e -> when (a > b) (e a) >> return b
               return x

-- MonadError instance

prop_monad_error_throw :: Integer -> Integer -> Property
prop_monad_error_throw a b = runExcept (runParserT p "" "") === Left a
  where p :: ParsecT Dec String (Except Integer) Integer
        p = throwError a >> return b

prop_monad_error_catch :: Integer -> Integer -> Property
prop_monad_error_catch a b =
  runExcept (runParserT p "" "") === Right (Right $ a + b)
  where p :: ParsecT Dec String (Except Integer) Integer
        p = (throwError a >> return b) `catchError` handler
        handler e = return (e + b)

-- Primitive combinators

prop_unexpected :: ErrorItem Char -> Property
prop_unexpected item = checkParser' p r s
  where p :: (MonadParsec e s m, Token s ~ Char) => m String
        p = unexpected item
        r = posErr 0 s [Unexpected item]
        s = ""

prop_failure
  :: Set (ErrorItem Char)
  -> Set (ErrorItem Char)
  -> Set Dec
  -> Property
prop_failure us ps xs = checkParser' p r s
  where p :: (MonadParsec Dec s m, Token s ~ Char) => m String
        p = failure us ps xs
        r = Left ParseError
          { errorPos        = nes (initialPos "")
          , errorUnexpected = us
          , errorExpected   = ps
          , errorCustom     = xs }
        s = ""

prop_label :: NonNegative Int -> NonNegative Int
           -> NonNegative Int -> String -> Property
prop_label a' b' c' l = checkParser' p r s
  where p :: (MonadParsec e s m, Token s ~ Char) => m String
        p = (++) <$> many (char 'a') <*> (many (char 'b') <?> l)
        r | null s = Right s
          | c > 0 = posErr (a + b) s $ [utok 'c', eeof]
            ++ [etok 'a' | b == 0]
            ++ (if null l
                  then []
                  else [if b == 0
                         then elabel l
                         else elabel ("rest of " ++ l)])
          | otherwise = Right s
        s = abcRow a b c
        [a,b,c] = getNonNegative <$> [a',b',c']

prop_hidden_0 :: NonNegative Int -> NonNegative Int
              -> NonNegative Int -> Property
prop_hidden_0 a' b' c' = checkParser' p r s
  where p :: (MonadParsec e s m, Token s ~ Char) => m String
        p = (++) <$> many (char 'a') <*> hidden (many (char 'b'))
        r | null s = Right s
          | c > 0  = posErr (a + b) s $ [utok 'c', eeof]
                     ++ [etok 'a' | b == 0]
          | otherwise = Right s
        s = abcRow a b c
        [a,b,c] = getNonNegative <$> [a',b',c']

prop_hidden_1 :: NonEmptyList Char -> String -> Property
prop_hidden_1 c' s = checkParser' p r s
  where p :: (MonadParsec e s m, Token s ~ Char) => m (Maybe String)
        p = optional (hidden $ string c)
        r | null s           = Right Nothing
          | c == s           = Right (Just s)
          | c `isPrefixOf` s = posErr cn s [utok (s !! cn), eeof]
          | otherwise        = posErr 0 s [utok (head s), eeof]
        c = getNonEmpty c'
        cn = length c

prop_try :: Char -> Char -> Char -> Property
prop_try pre ch1 ch2 = checkParser' p r s
  where p :: (MonadParsec e s m, Token s ~ Char) => m String
        p = try (sequence [char pre, char ch1])
          <|> sequence [char pre, char ch2]
        r = posErr 1 s [ueof, etok ch1, etok ch2]
        s = [pre]

prop_lookAhead_0 :: Bool -> Bool -> Bool -> Property
prop_lookAhead_0 a b c = checkParser' p r s
  where p :: (MonadParsec e s m, Token s ~ Char) => m Char
        p = do
          l <- lookAhead (oneOf "ab" <?> "label")
          guard (l == h)
          char 'a'
        h = head s
        r | null s = posErr 0 s [ueof, elabel "label"]
          | s == "a" = Right 'a'
          | h == 'b' = posErr 0 s [utok 'b', etok 'a']
          | h == 'c' = posErr 0 s [utok 'c', elabel "label"]
          | otherwise  = posErr 1 s [utok (s !! 1), eeof]
        s = abcRow a b c

prop_lookAhead_1 :: String -> Property
prop_lookAhead_1 s = checkParser' p r s
  where p :: (MonadParsec e s m, Token s ~ Char) => m ()
        p = lookAhead (some letterChar) >> fail emsg
        h = head s
        r | null s     = posErr 0 s [ueof, elabel "letter"]
          | isLetter h = posErr 0 s [cstm (DecFail emsg)]
          | otherwise  = posErr 0 s [utok h, elabel "letter"]
        emsg = "ops!"

prop_lookAhead_2 :: Bool -> Bool -> Bool -> Property
prop_lookAhead_2 a b c = checkParser' p r s
  where p :: (MonadParsec e s m, Token s ~ Char) => m Char
        p = lookAhead (some (char 'a')) >> char 'b'
        r | null s    = posErr 0 s [ueof, etok 'a']
          | a         = posErr 0 s [utok 'a', etok 'b']
          | otherwise = posErr 0 s [utok (head s), etok 'a']
        s = abcRow a b c

case_lookAhead_3 :: Assertion
case_lookAhead_3 = checkCase' p r s
  where p :: (MonadParsec e s m, Token s ~ Char) => m String
        p = lookAhead (char 'a' *> fail emsg)
        r = posErr 1 s [cstm (DecFail emsg)]
        emsg = "ops!"
        s = "abc"

prop_notFollowedBy_0 :: NonNegative Int -> NonNegative Int
                     -> NonNegative Int -> Property
prop_notFollowedBy_0 a' b' c' = checkParser' p r s
  where p :: (MonadParsec e s m, Token s ~ Char) => m String
        p = many (char 'a') <* notFollowedBy (char 'b') <* many (char 'c')
        r | b > 0     = posErr a s [utok 'b', etok 'a']
          | otherwise = Right (replicate a 'a')
        s = abcRow a b c
        [a,b,c] = getNonNegative <$> [a',b',c']

prop_notFollowedBy_1 :: NonNegative Int -> NonNegative Int
                     -> NonNegative Int -> Property
prop_notFollowedBy_1 a' b' c' = checkParser' p r s
  where p :: (MonadParsec e s m, Token s ~ Char) => m String
        p = many (char 'a')
          <* (notFollowedBy . notFollowedBy) (char 'c')
          <* many (char 'c')
        r | b == 0 && c > 0 = Right (replicate a 'a')
          | b > 0           = posErr a s [utok 'b', etok 'a']
          | otherwise       = posErr a s [ueof, etok 'a']
        s = abcRow a b c
        [a,b,c] = getNonNegative <$> [a',b',c']

prop_notFollowedBy_2 :: NonNegative Int -> NonNegative Int
                     -> NonNegative Int -> Property
prop_notFollowedBy_2 a' b' c' = checkParser' p r s
  where p :: (MonadParsec e s m, Token s ~ Char) => m String
        p = many (char 'a') <* notFollowedBy eof <* many anyChar
        r | b > 0 || c > 0 = Right (replicate a 'a')
          | otherwise      = posErr a s [ueof, etok 'a']
        s = abcRow a b c
        [a,b,c] = getNonNegative <$> [a',b',c']

case_notFollowedBy_3a :: Assertion
case_notFollowedBy_3a = checkCase' p r s
  where p :: (MonadParsec e s m, Token s ~ Char) => m ()
        p = notFollowedBy (char 'a' *> char 'c')
        r = Right ()
        s = "ab"

case_notFollowedBy_3b :: Assertion
case_notFollowedBy_3b = checkCase' p r s
  where p :: (MonadParsec e s m, Token s ~ Char) => m ()
        p = notFollowedBy (char 'a' *> char 'd') <* char 'c'
        r = posErr 0 s [utok 'a', etok 'c']
        s = "ab"

case_notFollowedBy_4a :: Assertion
case_notFollowedBy_4a = checkCase' p r s
  where p :: MonadParsec e s m => m ()
        p = notFollowedBy mzero
        r = Right ()
        s = "ab"

case_notFollowedBy_4b :: Assertion
case_notFollowedBy_4b = checkCase' p r s
  where p :: (MonadParsec e s m, Token s ~ Char) => m ()
        p = notFollowedBy mzero <* char 'c'
        r = posErr 0 s [utok 'a', etok 'c']
        s = "ab"

prop_withRecovery_0
  :: NonNegative Int
  -> NonNegative Int
  -> NonNegative Int
  -> Property
prop_withRecovery_0 a' b' c' = checkParser' p r s
  where
    p :: (MonadParsec Dec s m, Token s ~ Char)
      => m (Either (ParseError Char Dec) String)
    p = let g = count' 1 3 . char in v <$>
      withRecovery (\e -> Left e <$ g 'b') (Right <$> g 'a') <*> g 'c'
    v (Right x) y = Right (x ++ y)
    v (Left  m) _ = Left m
    r | a == 0 && b == 0 && c == 0 = posErr 0 s [ueof, etok 'a']
      | a == 0 && b == 0 && c >  3 = posErr 0 s [utok 'c', etok 'a']
      | a == 0 && b == 0           = posErr 0 s [utok 'c', etok 'a']
      | a == 0 && b >  3           = posErr 3 s [utok 'b', etok 'a', etok 'c']
      | a == 0 &&           c == 0 = posErr b s [ueof, etok 'a', etok 'c']
      | a == 0 &&           c >  3 = posErr (b + 3) s [utok 'c', eeof]
      | a == 0                     = Right (posErr 0 s [utok 'b', etok 'a'])
      | a >  3                     = posErr 3 s [utok 'a', etok 'c']
      |           b == 0 && c == 0 = posErr a s $ [ueof, etok 'c'] ++ ma
      |           b == 0 && c >  3 = posErr (a + 3) s [utok 'c', eeof]
      |           b == 0           = Right (Right s)
      | otherwise                  = posErr a s $ [utok 'b', etok 'c'] ++ ma
    ma = [etok 'a' | a < 3]
    s = abcRow a b c
    [a,b,c] = getNonNegative <$> [a',b',c']

case_withRecovery_1 :: Assertion
case_withRecovery_1 = checkCase' p r s
  where p :: MonadParsec e s m => m String
        p = withRecovery (const $ return "bar") (return "foo")
        r = Right "foo"
        s = "abc"

case_withRecovery_2 :: Assertion
case_withRecovery_2 = checkCase' p r s
  where p :: (MonadParsec e s m, Token s ~ Char) => m String
        p = withRecovery (\_ -> char 'a' *> mzero) (string "cba")
        r = posErr 0 s [utoks "a", etoks "cba"]
        s = "abc"

case_withRecovery_3a :: Assertion
case_withRecovery_3a = checkCase' p r s
  where p :: (MonadParsec e s m, Token s ~ Char) => m String
        p = withRecovery (const $ return "abd") (string "cba")
        r = Right "abd"
        s = "abc"

case_withRecovery_3b :: Assertion
case_withRecovery_3b = checkCase' p r s
  where p :: (MonadParsec e s m, Token s ~ Char) => m String
        p = withRecovery (const $ return "abd") (string "cba") <* char 'd'
        r = posErr 0 s [utok 'a', etoks "cba", etok 'd']
        s = "abc"

case_withRecovery_4a :: Assertion
case_withRecovery_4a = checkCase' p r s
  where p :: (MonadParsec e s m, Token s ~ Char) => m String
        p = withRecovery (const $ string "bc") (char 'a' *> mzero)
        r = Right "bc"
        s = "abc"

case_withRecovery_4b :: Assertion
case_withRecovery_4b = checkCase' p r s
  where p :: (MonadParsec e s m, Token s ~ Char) => m String
        p = withRecovery (const $ string "bc")
          (char 'a' *> char 'd' *> pure "foo") <* char 'f'
        r = posErr 3 s [ueof, etok 'f']
        s = "abc"

case_withRecovery_5 :: Assertion
case_withRecovery_5 = checkCase' p r s
  where p :: (MonadParsec e s m, Token s ~ Char) => m String
        p = withRecovery (\_ -> char 'b' *> fail emsg) (char 'a' *> fail emsg)
        r = posErr 1 s [cstm (DecFail emsg)]
        emsg = "ops!"
        s = "abc"

case_withRecovery_6a :: Assertion
case_withRecovery_6a = checkCase' p r s
  where p :: (MonadParsec e s m, Token s ~ Char) => m String
        p = withRecovery (const $ return "abd") (char 'a' *> mzero)
        r = Right "abd"
        s = "abc"

case_withRecovery_6b :: Assertion
case_withRecovery_6b = checkCase' p r s
  where p :: (MonadParsec e s m, Token s ~ Char) => m Char
        p = withRecovery (const $ return 'g') (char 'a' *> char 'd') <* char 'f'
        r = posErr 1 s [utok 'b', etok 'd', etok 'f']
        s = "abc"

case_withRecovery_7 :: Assertion
case_withRecovery_7 = checkCase' p r s
  where p :: (MonadParsec e s m, Token s ~ Char) => m Char
        p = withRecovery (const mzero) (char 'a' *> char 'd')
        r = posErr 1 s [utok 'b', etok 'd']
        s = "abc"

case_eof :: Assertion
case_eof = checkCase' eof (Right ()) ""

prop_token :: Maybe Char -> String -> Property
prop_token mtok s = checkParser' p r s
  where p :: (MonadParsec e s m, Token s ~ Char) => m Char
        p = token testChar mtok
        testChar x = if isLetter x
          then Right x
          else Left (E.singleton (Tokens $ nes x), E.empty, E.empty)
        h = head s
        r | null s = posErr 0 s $ ueof : maybeToList (etok <$> mtok)
          | isLetter h && length s == 1 = Right (head s)
          | isLetter h && length s > 1 = posErr 1 s [utok (s !! 1), eeof]
          | otherwise = posErr 0 s [utok h]

prop_tokens_0 :: String -> String -> Property
prop_tokens_0 a = checkString (tokens (==) a) a (==)

prop_tokens_1 :: String -> String -> String -> Property
prop_tokens_1 pre post post' =
  not (post `isPrefixOf` post') ==>
  (leftover === "" .||. leftover === s)
  where p :: Parser String
        p = tokens (==) (pre ++ post)
        s = pre ++ post'
        st = stateFromInput s
        leftover = stateInput . fst $ runParser' p st

-- Parser state combinators

prop_state_pos :: State String -> SourcePos -> Property
prop_state_pos st pos = runParser' p st === r
  where p = (setPosition pos >> getPosition) :: Parser SourcePos
        r = (f st pos, Right pos)
        f (State s (_:|xs) w) y = State s (y:|xs) w

prop_state_pushPosition :: State String -> SourcePos -> Property
prop_state_pushPosition st pos = fst (runParser' p st) === r
  where p = pushPosition pos :: Parser ()
        r = st { statePos = NE.cons pos (statePos st) }

prop_state_popPosition :: State String -> Property
prop_state_popPosition st = fst (runParser' p st) === r
  where p = popPosition :: Parser ()
        r = st { statePos = fromMaybe pos (snd (NE.uncons pos)) }
        pos = statePos st

prop_state_input :: String -> Property
prop_state_input s = p /=\ s
  where p = do
          st0    <- getInput
          guard (null st0)
          setInput s
          result <- string s
          st1    <- getInput
          guard (null st1)
          return result

prop_state_tab :: Pos -> Property
prop_state_tab w = p /=\ w
  where p = setTabWidth w >> getTabWidth

prop_state :: State String -> State String -> Property
prop_state s1 s2 = checkParser' p r s
  where p :: MonadParsec Dec String m => m (State String)
        p = do
          st <- getParserState
          guard (st == State s (nes $ initialPos "") defaultTabWidth)
          setParserState s1
          updateParserState (f s2)
          liftM2 const getParserState (setInput "")
        f (State s1' pos w) (State s2' _ _) = State (max s1' s2' ) pos w
        r = Right (f s2 s1)
        s = ""

-- Running a parser

prop_parseMaybe :: String -> String -> Property
prop_parseMaybe s s' = parseMaybe p s === r
  where p = string s' :: Parser String
        r = if s == s' then Just s else Nothing

prop_runParser' :: State String -> String -> Property
prop_runParser' st s = runParser' p st === r
  where p = string s
        r = emulateStrParsing st s

prop_runParserT' :: State String -> String -> Property
prop_runParserT' st s = runIdentity (runParserT' p st) === r
  where p = string s
        r = emulateStrParsing st s

emulateStrParsing
  :: State String
  -> String
  -> (State String, Either (ParseError Char Dec) String)
emulateStrParsing st@(State i (pos:|z) t) s =
  if l == length s
    then (State (drop l i) (updatePosString t pos s :| z) t, Right s)
    else (st, posErr' (pos:|z) (etoks s : [utoks (take (l + 1) i)]))
  where l = length (takeWhile id $ zipWith (==) s i)

-- Additional tests to check returned state on failure

prop_stOnFail_0 :: Positive Int -> Positive Int -> Property
prop_stOnFail_0 na' nb' = runParser' p (stateFromInput s) === (i, r)
  where i = let (Left x) = r in State "" (errorPos x) defaultTabWidth
        na = getPositive na'
        nb = getPositive nb'
        p = try (many (char 'a') <* many (char 'b') <* char 'c')
          <|> (many (char 'a') <* char 'c')
        r = posErr (na + nb) s [etok 'b', etok 'c', ueof]
        s = replicate na 'a' ++ replicate nb 'b'

prop_stOnFail_1 :: Positive Int -> Pos -> Property
prop_stOnFail_1 na' t = runParser' p (stateFromInput s) === (i, r)
  where i = let (Left x) = r in State "" (errorPos x) t
        na = getPositive na'
        p = many (char 'a') <* setTabWidth t <* fail emsg
        r = posErr na s [cstm (DecFail emsg)]
        s = replicate na 'a'
        emsg = "failing now!"

prop_stOnFail_2 :: String -> Char -> Property
prop_stOnFail_2 s' ch = runParser' p (stateFromInput s) === (i, r)
  where i = let (Left x) = r in State [ch] (errorPos x) defaultTabWidth
        r = posErr (length s') s [utok ch, eeof]
        p = string s' <* eof
        s = s' ++ [ch]

prop_stOnFail_3 :: String -> Property
prop_stOnFail_3 s = runParser' p (stateFromInput s) === (i, r)
  where i = let (Left x) = r in State s (errorPos x) defaultTabWidth
        r = posErr 0 s [if null s then ueof else utok (head s)]
        p = notFollowedBy (string s)

stateFromInput :: s -> State s
stateFromInput s = State s (nes $ initialPos "") defaultTabWidth

-- ReaderT instance of MonadParsec

prop_ReaderT_try :: Char -> Char -> Char -> Property
prop_ReaderT_try pre ch1 ch2 = checkParser (runReaderT p (s1, s2)) r s
  where s1 = pre : [ch1]
        s2 = pre : [ch2]
        getS1 = asks fst
        getS2 = asks snd
        p = try (g =<< getS1) <|> (g =<< getS2)
        g = sequence . fmap char
        r = posErr 1 s [ueof, etok ch1, etok ch2]
        s = [pre]

prop_ReaderT_notFollowedBy :: NonNegative Int -> NonNegative Int
                           -> NonNegative Int -> Property
prop_ReaderT_notFollowedBy a' b' c' = checkParser (runReaderT p 'a') r s
  where [a,b,c] = getNonNegative <$> [a',b',c']
        p = many (char =<< ask) <* notFollowedBy eof <* many anyChar
        r | b > 0 || c > 0 = Right (replicate a 'a')
          | otherwise      = posErr a s [ueof, etok 'a']
        s = abcRow a b c

-- StateT instance of MonadParsec

prop_StateT_alternative :: Integer -> Property
prop_StateT_alternative n =
  checkParser (L.evalStateT p 0) (Right n) "" .&&.
  checkParser (S.evalStateT p' 0) (Right n) ""
  where p  = L.put n >> ((L.modify (* 2) >>
                          void (string "xxx")) <|> return ()) >> L.get
        p' = S.put n >> ((S.modify (* 2) >>
                          void (string "xxx")) <|> return ()) >> S.get

prop_StateT_lookAhead :: Integer -> Property
prop_StateT_lookAhead n =
  checkParser (L.evalStateT p 0) (Right n) "" .&&.
  checkParser (S.evalStateT p' 0) (Right n) ""
  where p  = L.put n >> lookAhead (L.modify (* 2) >> eof) >> L.get
        p' = S.put n >> lookAhead (S.modify (* 2) >> eof) >> S.get

prop_StateT_notFollowedBy :: Integer -> Property
prop_StateT_notFollowedBy n = checkParser (L.runStateT p 0) r "abx" .&&.
                              checkParser (S.runStateT p' 0) r "abx"
  where p = do
          L.put n
          let notEof = notFollowedBy (L.modify (* 2) >> eof)
          some (try (anyChar <* notEof)) <* char 'x'
        p' = do
          S.put n
          let notEof = notFollowedBy (S.modify (* 2) >> eof)
          some (try (anyChar <* notEof)) <* char 'x'
        r = Right ("ab", n)

-- WriterT instance of MonadParsec

prop_WriterT :: String -> String -> Property
prop_WriterT pre post =
  checkParser (L.runWriterT p) r "abx" .&&.
  checkParser (S.runWriterT p') r "abx"
  where logged_letter  = letterChar >>= \x -> L.tell [x] >> return x
        logged_letter' = letterChar >>= \x -> L.tell [x] >> return x
        logged_eof     = eof >> L.tell "EOF"
        logged_eof'    = eof >> L.tell "EOF"
        p = do
          L.tell pre
          cs <- L.censor (fmap toUpper) $
                  some (try (logged_letter <* notFollowedBy logged_eof))
          L.tell post
          void logged_letter
          return cs
        p' = do
          L.tell pre
          cs <- L.censor (fmap toUpper) $
                  some (try (logged_letter' <* notFollowedBy logged_eof'))
          L.tell post
          void logged_letter'
          return cs
        r = Right ("ab", pre ++ "AB" ++ post ++ "x")

nes :: a -> NonEmpty a
nes x = x :| []
{-# INLINE nes #-}
