{-# LANGUAGE PackageImports #-}

module Chromar.Rule.Attributes
    ( AgentType(..)
    , fillPat, fillAttrs
    ) where

import qualified Data.Map as M (fromList, toList, difference, union)
import qualified Data.Set as S (Set, fromList, toList, difference)
import "template-haskell" Language.Haskell.TH
    ( Q, Dec(..), Exp(..), Info(..), FieldExp, Con(..)
    , reify, mkName, nameBase, newName
    )

import Chromar.Rule.Syntax (SRule(..), Nm)

data AgentType = AgentT Nm (S.Set Nm) deriving (Show)

getN :: AgentType -> Nm
getN (AgentT nm _) = nm

getIntf :: AgentType -> S.Set Nm
getIntf (AgentT _ iface) = iface

intf :: Exp -> [FieldExp]
intf (RecConE _ fexps) = fexps
intf _ = error "Expected records"

fst3 :: (a, b, c) -> a
fst3 (x, _, _) = x

getType :: Con -> AgentType
getType (RecC nm ifce) = AgentT (nameBase nm) (S.fromList fNames) where
    fNames = nameBase . fst3 <$> ifce
getType _ = error "Expected records"

extractIntf :: Info -> [AgentType]
extractIntf (TyConI (DataD _ _ _ _ cons _)) = getType <$> cons
extractIntf _ = error "Expected type constructor"

createMFExp :: Nm -> Q FieldExp
createMFExp nm = do
    varNm <- newName nm
    return (mkName nm, VarE varNm)

fillPat :: AgentType -> Exp -> Q Exp
fillPat typ (RecConE nm fexps) = do
    let fIntf = getIntf typ
    let pIntf = S.fromList $ nameBase . fst <$> fexps
    let mAttrs = S.difference fIntf pIntf
    mFExps <- traverse createMFExp (S.toList mAttrs)
    return $ RecConE nm (fexps ++ mFExps)
fillPat _ _ = error "Expected record patterns"

lookupType :: [AgentType] -> Nm -> AgentType
lookupType ats nm = head $ filter (\at -> getN at == nm) ats

fPat :: [AgentType] -> Exp -> Q Exp
fPat ats e@(RecConE nm _) = fillPat at e where
    at = lookupType ats (nameBase nm)
fPat _ _ = error "Expected record patterns"

fRExp :: Exp -> Exp -> Exp
fRExp lexp (RecConE nm rIntf) = RecConE nm (M.toList pIntf') where
    fIntf = M.fromList (intf lexp)
    pIntf = M.fromList rIntf
    pIntf' = M.union pIntf (M.difference fIntf pIntf)
fRExp _ _ = error "Expected records"

sameType :: Exp -> Exp -> Bool
sameType (RecConE nm _) (RecConE nm' _) = nm == nm'
sameType _ _ = error "Expected records"

tRExp :: Exp -> Exp -> Exp
tRExp l r
    | sameType l r = fRExp l r
    | otherwise = r

fillAttrs :: SRule -> Q SRule
fillAttrs
    SRule
        { lexps = les
        , rexps = res
        , multExps = m
        , srate = r
        , cond = c
        } = do
    info <- reify (mkName "Agent")
    let aTyps = extractIntf info
    les' <- traverse (fPat aTyps) les
    return
        SRule
            { lexps = les'
            , rexps = zipWith tRExp les' res
            , multExps = m
            , srate = r
            , cond = c
            }