{-# LANGUAGE TemplateHaskell #-}

module Chromar.RExprs where

import Language.Haskell.TH
import Language.Haskell.TH.Quote
import Data.Set (Set)
import qualified Data.Set as Set
import Text.ParserCombinators.Parsec
import Data.List
import Text.Parsec
import Language.Haskell.Meta.Parse
import Language.Haskell.TH.Syntax
import Text.Parsec.String (Parser)
import Text.Parsec.Language (emptyDef)
import Text.Parsec.Token (makeTokenParser)
import Data.Fixed
import Data.Maybe

import qualified Text.Parsec.Token as Tok

import Chromar.Multiset
import Chromar.Core

data ErF a b = ErF { at :: Multiset a -> Time -> b }

zipEr2 :: ErF a b -> ErF a c -> ErF a (b, c)
zipEr2 e1 e2 =
    ErF
    { at = \s t -> (at e1 s t, at e2 s t)
    }

zipEr3 :: ErF a b -> ErF a c -> ErF a d -> ErF a (b, c, d)
zipEr3 e1 e2 e3 =
    ErF
    { at = \s t -> (at e1 s t, at e2 s t, at e3 s t)
    }

zipEr4 :: ErF a b -> ErF a b1 -> ErF a b2 -> ErF a b3 -> ErF a (b, b1, b2, b3)
zipEr4 e1 e2 e3 e4 =
    ErF
    { at = \s t -> (at e1 s t, at e2 s t, at e3 s t, at e4 s t)
    }

zipEr5
    :: ErF a b
    -> ErF a b1
    -> ErF a b2
    -> ErF a b3
    -> ErF a b4
    -> ErF a (b, b1, b2, b3, b4)
zipEr5 e1 e2 e3 e4 e5 =
    ErF
    { at = \s t -> (at e1 s t, at e2 s t, at e3 s t, at e4 s t, at e5 s t)
    }

repeatEvery :: ErF a Time -> ErF a b -> ErF a b
repeatEvery et er =
    ErF
    { at = \s t -> at er s (mod' t (at et s t))
    }

when :: ErF a Bool -> ErF a b -> ErF a (Maybe b)
when eb er =
    ErF
    { at =
        \s t ->
             if at eb s t
                 then Just (at er s t)
                 else Nothing
    }

orElse :: ErF a (Maybe b) -> ErF a b -> ErF a b
e1 `orElse` e2 =
    ErF
    { at = \s t -> fromMaybe (at e2 s t) (at e1 s t)
    }

time =
    ErF
    { at = \s t -> t
    }

obs :: (a -> Bool) -> ErF a (a -> b -> b) -> ErF a b -> ErF a b
obs f comb i =
    ErF
    { at = \s t -> aggregate (at comb s t) (at i s t) . select f $ s
    }

select :: (a -> Bool) -> Multiset a -> Multiset a
select f = filter (\(el, _) -> f el)

aggregate :: (a -> b -> b) -> b -> Multiset a -> b
aggregate f i s = foldr f i (toList s)

mkEr :: (Multiset a -> Time -> b) -> ErF a b
mkEr f = ErF { at = f }

type Nm = String

data Er
    = HExpr (Set Name)
            Exp
    | Time
    | When Er
           Er
           Er
    | Repeat Er
             Er
    | Obs Nm
          Er
          Er
    deriving (Show)

langDef =
    emptyDef
    { Tok.reservedOpNames = ["$"]
    , Tok.reservedNames = ["repeatEvery", "when", "else", "select", "aggregate", "time"]
    }

lexer :: Tok.TokenParser ()
lexer = Tok.makeTokenParser langDef

op = Tok.reservedOp lexer

name = Tok.identifier lexer

commaSep = Tok.commaSep lexer

braces = Tok.braces lexer

squares = Tok.squares lexer

whiteSpace = Tok.whiteSpace lexer


getEsc :: String -> Set Name
getEsc "" = Set.empty
getEsc (c:cs)
    | c == '$' = Set.union (Set.fromList [mkName ident]) (getEsc rest)
    | otherwise = getEsc cs
  where
    (ident, rest) = getIdent cs ""
    getIdent "" acc = (acc, "")
    getIdent (c:cs) acc =
        if c == '$'
            then (acc, cs)
            else getIdent cs (acc ++ [c])

rmEscChar :: String -> String
rmEscChar cs = [c | c <- cs, c /= '$']

mkExp :: String -> Exp
mkExp s = case parseExp s of
  (Left err) -> error err
  (Right e) -> e

hExpr :: Parser Er
hExpr = do
  Tok.symbol lexer "{"
  s <- many1 (noneOf ['}'])
  Tok.symbol lexer "}"
  let nms = getEsc s
  case parseExp (rmEscChar s) of
    Left err -> error err
    Right e -> return (HExpr nms e)

parseEr :: Parser Er
parseEr =
    whenExpr <|> repeatExpr <|> obsExpr <|> timeExpr <|> parensExpr <|>
    hExpr <|> spaceExpr
    
whenExpr :: Parser Er
whenExpr = do
  op "when"
  er1 <- parseEr
  er2 <- parseEr
  op "else"
  er3 <- parseEr
  return $ When er1 er2 er3

repeatExpr :: Parser Er
repeatExpr = do
  op "repeatEvery"
  er1 <- parseEr
  er2 <- parseEr
  return $ Repeat er1 er2

obsExpr :: Parser Er
obsExpr = do
  op "select"
  nm <- Tok.identifier lexer
  op ";"
  op "aggregate"
  er1 <- parseEr
  er2 <- parseEr
  return $ Obs nm er1 er2

timeExpr :: Parser Er
timeExpr = do
  op "time"
  return Time

parensExpr :: Parser Er
parensExpr = do
    er <- Text.Parsec.between (Tok.symbol lexer "(") (Tok.symbol lexer ")") parseEr
    return er

spaceExpr :: Parser Er
spaceExpr = do
  whiteSpace
  er <- parseEr
  whiteSpace
  return er

mkErApp :: Name -> Exp
mkErApp nm =
    ParensE
        (AppE
             (AppE (AppE (VarE $ mkName "at") (VarE nm)) (VarE $ mkName "s"))
             (VarE $ mkName "t"))

lExp :: Set Name -> Exp -> Exp
lExp nms var@(VarE nm) =
    if Set.member nm nms
        then mkErApp nm
        else var
lExp nms (AppE e1 e2) = AppE (lExp nms e1) (lExp nms e2)
lExp nms (TupE exps) = TupE (map (lExp nms) exps)
lExp nms (ListE exps) = ListE (map (lExp nms) exps)
lExp nms (UInfixE e1 e2 e3) = UInfixE (lExp nms e1) (lExp nms e2) (lExp nms e3)
lExp nms (ParensE e) = ParensE (lExp nms e)
lExp nms (LamE pats e) = LamE pats (lExp nms e)
lExp nms (CompE stmts) = CompE (map (tStmt nms) stmts)
  where
    tStmt nms (BindS p e) = BindS p (lExp nms e)
    tStmt nms (NoBindS e) = NoBindS (lExp nms e)
lExp nms (InfixE me1 e me2) =
    InfixE (fmap (lExp nms) me1) (lExp nms e) (fmap (lExp nms) me2)
lExp nms (LitE lit) = LitE lit
lExp nms (ConE nm) = ConE nm
lExp nms (RecConE nm fexps) = RecConE nm (map (tFExp nms) fexps)
  where
    tFExp nms (nm, exp) = (nm, lExp nms exp)
lExp nms _ = undefined

mkLiftExp :: Set Name -> Exp -> Exp
mkLiftExp nms body = LamE args (lExp nms body)
  where
    args = [VarP $ mkName "s", VarP $ mkName "t"]

mkWhenExp :: Exp -> Exp -> Exp -> Exp
mkWhenExp eb e1 e2 = AppE (AppE (VarE $ mkName "orElse") whenE) e2
  where
    whenE = AppE (AppE (VarE $ mkName "when") eb) e1

mkRepeatExp :: Exp -> Exp -> Exp
mkRepeatExp et e = AppE (AppE (VarE $ mkName "repeatEvery") et) e

mkObsExp :: Nm -> Exp -> Exp -> Exp
mkObsExp nm combE initE = AppE (AppE selectE combE) initE
  where
    selF = "is" ++ nm
    selectE = AppE (VarE $ mkName "obs") (VarE $ mkName selF)

quoteEr :: Er -> Exp
quoteEr Time = VarE $ mkName "time"
quoteEr (HExpr nms e) = AppE (VarE $ mkName "mkEr") (mkLiftExp nms e)
quoteEr (When er1 er2 er3) = mkWhenExp (quoteEr er1) (quoteEr er2) (quoteEr er3)
quoteEr (Repeat er1 er2) = mkRepeatExp (quoteEr er1) (quoteEr er2)
quoteEr (Obs nm er1 er2) = mkObsExp nm (quoteEr er1) (quoteEr er2)

erQuoter :: String -> Q Exp
erQuoter s = case parse parseEr "er" s of
  Left err -> error (show err)
  Right e -> return $ quoteEr e
---- parse the quote into Er then create the functions per the semantics

er :: QuasiQuoter
er =
    QuasiQuoter
    { quoteExp = erQuoter
    , quotePat = undefined
    , quoteDec = undefined
    , quoteType = undefined
    }

------------- testing
contents = "repeatEvery {5} (when {$light$ + 1} {5} else {1})"

go = case parse parseEr "er" contents of
  (Left err) -> error (show err)
  (Right val) -> val
