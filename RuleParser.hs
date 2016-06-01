module RuleParser where

import Text.ParserCombinators.Parsec.Combinator
import Text.ParserCombinators.Parsec
import Text.Parsec.Token
import Language.Haskell.TH
import Language.Haskell.Meta.Parse
import Control.Monad


data SRule = SRule { lpats :: [Pat],
                     lexps :: [Exp],
                     rexps :: [Exp],
                     rate  :: Exp,
                     cond  :: Exp } deriving (Show)
                             

parseAgent :: Parser String
parseAgent = do
  spaces
  s <- many1 (noneOf [',', '}'])
  char '}'
  spaces
  return (s ++ "}")


parseRuleSide :: Parser [String]
parseRuleSide = do
  spaces
  sepBy parseAgent (char ',')


arrowSpaces :: Parser ()
arrowSpaces = do
  spaces
  string "-->"
  spaces


parseRate :: Parser String
parseRate = do
  char '@'
  spaces
  many (noneOf "( ")


parseCond :: Parser String
parseCond = do
  char '('
  spaces
  p <- many1 (noneOf ")")
  char ')'
  return p
  

createExps :: [String] -> [Exp]
createExps exps = case mapM parseExp exps of
  Left  s     -> error s
  Right pexps -> pexps


createPats :: [String] -> [Pat]
createPats pats = case mapM parsePat pats of
  Left s      -> error s
  Right ppats -> ppats


createExp :: String -> Exp
createExp exp = case parseExp exp of
  Left s    -> error s
  Right exp -> exp


parseRule :: Parser SRule
parseRule = do
  left <- parseRuleSide
  arrowSpaces
  right <- parseRuleSide
  spaces
  r <- parseRate
  spaces
  c <- parseCond
  return SRule{ lpats = createPats left,
                lexps = createExps left,
                rexps = createExps right,
                rate  = createExp r,
                cond  = createExp c }

--- for testing
readExpr :: String -> SRule
readExpr input = case parse parseRule "rules" input of
    Left err  -> error (show err)
    Right val -> val