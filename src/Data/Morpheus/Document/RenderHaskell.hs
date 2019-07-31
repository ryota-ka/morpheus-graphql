{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE NamedFieldPuns    #-}
{-# LANGUAGE OverloadedStrings #-}

module Data.Morpheus.Document.RenderHaskell
  ( renderHaskellDocument
  ) where

import           Data.ByteString.Lazy.Char8        (ByteString)
import           Data.Maybe                        (catMaybes)
import           Data.Semigroup                    ((<>))
import           Data.Text                         (Text, intercalate, pack, toUpper)
import qualified Data.Text                         as T (concat, head, tail)
import qualified Data.Text.Lazy                    as LT (fromStrict)
import           Data.Text.Lazy.Encoding           (encodeUtf8)

-- MORPHEUS
import           Data.Morpheus.Types.Internal.Data (DataArgument, DataField (..), DataFullType (..), DataLeaf (..),
                                                    DataType (..), DataTypeLib, DataTypeWrapper (..), allDataTypes)

renderHaskellDocument :: DataTypeLib -> ByteString
renderHaskellDocument lib = encodeText $ renderLanguageExtensions <> renderExports <> renderImports <> types
  where
    encodeText = encodeUtf8 . LT.fromStrict
    types = intercalate "\n\n" $ map renderHaskellType visibleTypes
    visibleTypes = allDataTypes lib

renderExports :: Text
renderExports = "module Schema where\n\n"

renderIndent :: Text
renderIndent = "  "

defineData :: Text -> Text
defineData name = "data " <> name <> " = "

defineCon :: Text -> Text
defineCon name = name <> " "

unionType :: [Text] -> Text
unionType ls = "\n" <> renderIndent <> intercalate ("\n" <> renderIndent <> "| ") ls <> " deriving (Generic)"

typeAssignment :: Text -> Text -> Text
typeAssignment key value = key <> " :: " <> value

renderLanguageExtensions :: Text
renderLanguageExtensions = "{-# LANGUAGE DeriveGeneric #-}\n" <> "\n"

renderImports :: Text
renderImports = T.concat (map renderImport imports) <> "\n"
  where
    renderImport (src, list) = "import  " <> src <> "  (" <> intercalate "," list <> ")\n"
    --------------------------------------------------------------------------------------
    imports =
      [ ("GHC.Generics", ["Generic"])
      , ("Data.Morpheus.KIND", ["SCALAR", "ENUM", "INPUT_OBJECT", "OBJECT", "OBJECT"])
      , ("Data.Morpheus.Types", ["ResM", "GQLType(..)"])
      ]

renderHaskellType :: (Text, DataFullType) -> Text
renderHaskellType (name, dataType) = typeIntro <> defineData name <> renderType dataType
  where
    renderType (Leaf (LeafScalar _)) = defineCon name <> "Int String" <> defineTypeClass "SCALAR"
    renderType (Leaf (LeafEnum DataType {typeData})) = unionType typeData <> defineTypeClass "ENUM"
    renderType (Union DataType {typeData}) = renderUnion name typeData <> defineTypeClass "UNION"
    renderType (InputObject DataType {typeData}) =
      defineCon name <> renderDataObject renderInputField typeData <> defineTypeClass "INPUT_OBJECT"
    renderType (InputUnion _) = "\n -- Error: Input Union Not Supported"
    renderType (OutputObject DataType {typeData}) =
      defineCon name <> renderDataObject renderField typeData <> defineTypeClass "OBJECT"
    ----------------------------------------------------------------------------------------------------------
    typeIntro = "\n\n ---- GQL " <> name <> " ------------------------------- \n"
    ----------------------------------------------------------------------------------------------------------
    defineTypeClass kind =
      "\n\ninstance GQLType " <> name <> " where\n" <> renderIndent <> "KIND " <> name <> " = " <> kind

renderUnion :: Text -> [DataField ()] -> Text
renderUnion typeName = unionType . map renderElem
  where
    renderElem DataField {fieldType} = defineCon (typeName <> "_" <> toUpper fieldType) <> fieldType

renderObject :: (a -> (Text, Maybe Text)) -> [a] -> Text
renderObject f list = intercalate "\n\n" $ renderMainType : catMaybes types
  where
    renderMainType = "\n  { " <> intercalate ("\n  ," <> renderIndent) fields <> "\n  } deriving (Generic)"
    (fields, types) = unzip (map f list)

renderDataObject :: ((Text, DataField a) -> (Text, Maybe Text)) -> [(Text, DataField a)] -> Text
renderDataObject f list = renderObject f (ignoreHidden list)
  where
    ignoreHidden :: [(Text, DataField a)] -> [(Text, DataField a)]
    ignoreHidden = filter (not . fieldHidden . snd)

renderMaybe :: Text -> Text
renderMaybe typeName = "Maybe " <> typeName

renderList :: Text -> Text
renderList typeName = "[" <> typeName <> "]"

renderTuple :: Text -> Text
renderTuple typeName = "(" <> typeName <> ")"

renderWrappedType :: [DataTypeWrapper] -> Text -> Text
renderWrappedType [] typeName                          = renderMaybe typeName
renderWrappedType [NonNullType] typeName               = typeName
renderWrappedType (NonNullType:(ListType:xs)) typeName = renderList $ renderWrappedType xs typeName
renderWrappedType (ListType:xs) typeName               = renderMaybe $ renderList $ renderWrappedType xs typeName
renderWrappedType (NonNullType:xs) typeName            = renderWrappedType xs typeName

renderInputField :: (Text, DataField ()) -> (Text, Maybe Text)
renderInputField (key, DataField {fieldTypeWrappers, fieldType}) =
  (key `typeAssignment` renderWrappedType fieldTypeWrappers fieldType, Nothing)

renderField :: (Text, DataField [(Text, DataArgument)]) -> (Text, Maybe Text)
renderField (key, DataField {fieldTypeWrappers, fieldType, fieldArgs}) =
  (key `typeAssignment` argTypeName <> " -> ResM " <> result fieldTypeWrappers, argTypes)
  where
    result wrappers@(NonNullType:_) = renderWrappedType wrappers fieldType
    result wrappers                 = renderTuple (renderWrappedType wrappers fieldType)
    (argTypeName, argTypes) = renderArguments fieldArgs
    renderArguments :: [(Text, DataArgument)] -> (Text, Maybe Text)
    renderArguments [] = ("()", Nothing)
    renderArguments list =
      ( fieldArgTypeName
      , Just (defineData fieldArgTypeName <> defineCon fieldArgTypeName <> renderDataObject renderInputField list))
      where
        fieldArgTypeName = "Arg" <> camelCase key
        camelCase :: Text -> Text
        camelCase ""   = ""
        camelCase text = toUpper (pack [T.head text]) <> T.tail text
