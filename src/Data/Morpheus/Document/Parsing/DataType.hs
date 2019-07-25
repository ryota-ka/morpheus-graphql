{-# LANGUAGE NamedFieldPuns    #-}
{-# LANGUAGE OverloadedStrings #-}

module Data.Morpheus.Document.Parsing.DataType
  ( parseDataType
  ) where

{--}
import           Data.Morpheus.Document.Parsing.Terms (Parser, nonNull, parseAssignment, qualifier, token)
import           Data.Morpheus.Types.Internal.Data    (DataArgument, DataField (..), DataFingerprint (..),
                                                       DataFullType (..), DataOutputField, DataOutputObject,
                                                       DataType (..), DataTypeKind (..), DataTypeWrapper (..), Key)
import           Data.Text                            (Text)
import           Text.Megaparsec                      (between, label, many, sepEndBy, (<|>))
import           Text.Megaparsec.Char                 (char, space)

wrapMock :: Parser ([DataTypeWrapper], Text)
wrapMock = do
  mock <- token
  space
  return ([], mock)

insideList :: Parser ([DataTypeWrapper], Text)
insideList =
  between
    (char '[' *> space)
    (char ']' *> space)
    (do (list, name) <- wrapMock <|> insideList
        nonNull' <- nonNull
        return ((ListType : nonNull') ++ list, name))

wrappedSignature :: Parser ([DataTypeWrapper], Text)
wrappedSignature = do
  sig <- insideList <|> wrapMock
  space
  return sig

dataArgument :: Parser (Text, DataArgument)
dataArgument =
  label "operatorArgument" $ do
    ((fieldName, _), (wrappers', fieldType)) <- parseAssignment qualifier wrappedSignature
    nonNull' <- nonNull
    pure
      ( fieldName
      , DataField
          { fieldArgs = ()
          , fieldName
          , fieldKind = KindObject -- TODO : realKinds
          , fieldType
          , fieldTypeWrappers = nonNull' ++ wrappers'
          , fieldHidden = False
          })

entries :: Parser [(Key, DataOutputField)]
entries = label "entries" $ between (char '{' *> space) (char '}' *> space) (entry `sepEndBy` many (char ',' *> space))
  where
    entry =
      label "entry" $ do
        ((fieldName, _), (wrappers', fieldType)) <- parseAssignment qualifier wrappedSignature
        nonNull' <- nonNull
        -- variables <- parseMaybeTuple dataArgument
        return
          ( fieldName
          , DataField
              { fieldArgs = []
              , fieldName
              , fieldKind = KindObject -- TODO : realKinds
              , fieldType
              , fieldTypeWrappers = nonNull' ++ wrappers'
              , fieldHidden = False
              })

parseDataType :: Parser (Text, DataFullType)
parseDataType =
  label "operator" $ do
    typeName <- token
    typeData <- entries
    pure
      ( typeName
      , OutputObject $
        DataType
          {typeName, typeDescription = "", typeFingerprint = SystemFingerprint "", typeVisibility = True, typeData})