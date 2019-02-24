{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE FlexibleInstances , FlexibleContexts , TypeOperators #-}

module Data.Morpheus.Generics.GenericMap
    ( GenericMap(..)
    , getField
    , initMeta
    )
where

import           GHC.Generics
import qualified Data.Maybe     as       M
import qualified Data.Text      as       T
import qualified Data.Morpheus.Types.Types as G


-- type D1 = M1 D
-- type C1 = M1 C
-- type S1 = M1 S
-- M1 : Meta-information (constructor names, etc.)
-- D  :Datatype : Class for dataTypes that represent dataTypes
-- C :Constructor :
-- S - Selector: Class for dataTypes that represent records
-- Rep = D1 (...)  (C1 ...) (S1 (...) :+: D1 (...)  (C1 ...) (S1 (...)

initMeta = G.MetaInfo { G.className = "", G.cons = "", G.key = "" }

getField :: G.MetaInfo -> G.SelectionSet -> G.Eval G.QuerySelection
getField meta gql = pure $ M.fromMaybe G.QNull (lookup (G.key meta) gql)

class GenericMap f where
    encodeFields:: G.MetaInfo -> G.SelectionSet -> f a -> [(T.Text, G.EvalIO G.JSType)]

instance GenericMap U1  where
    encodeFields _ _  _ = []

instance (Selector s, GenericMap f) => GenericMap (M1 S s f) where
    encodeFields meta gql m@(M1 src) = encodeFields (meta{ G.key = T.pack $ selName m}) gql src

instance (Datatype c, GenericMap f) => GenericMap (M1 D c f)  where
    encodeFields meta gql m@(M1 src) = encodeFields (meta{ G.className = T.pack $ datatypeName m}) gql src

instance (Constructor c  , GenericMap f) => GenericMap (M1 C c f)  where
    encodeFields meta gql m@(M1 src) =  encodeFields (meta{ G.cons = T.pack $ conName m}) gql src

instance (GenericMap f , GenericMap g ) => GenericMap (f :*: g)  where
    encodeFields meta gql  (a :*: b) = encodeFields meta gql a ++ encodeFields meta gql b
