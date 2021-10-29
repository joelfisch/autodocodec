{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

module Autodocodec.Aeson.DocumentSpec (spec) where

import Autodocodec
import Autodocodec.Aeson
import Autodocodec.Usage
import qualified Data.Aeson as JSON
import Data.Data
import Data.GenValidity
import Data.GenValidity.Aeson ()
import Data.GenValidity.Containers ()
import Data.GenValidity.Scientific ()
import Data.GenValidity.Text ()
import Data.Int
import Data.List.NonEmpty (NonEmpty (..))
import Data.Scientific
import Data.Text (Text)
import qualified Data.Text.Lazy as LT
import Data.Word
import GHC.Generics (Generic)
import Test.QuickCheck
import Test.Syd
import Test.Syd.Aeson
import Test.Syd.Validity
import Test.Syd.Validity.Utils

spec :: Spec
spec = do
  jsonSchemaSpec @Bool "bool"
  jsonSchemaSpec @Ordering "ordering"
  jsonSchemaSpec @Char "char"
  jsonSchemaSpec @Text "text"
  jsonSchemaSpec @LT.Text "lazy-text"
  jsonSchemaSpec @String "string"
  jsonSchemaSpec @Scientific "scientific"
  jsonSchemaSpec @JSON.Value "value"
  jsonSchemaSpec @Int "int"
  jsonSchemaSpec @Int8 "int8"
  jsonSchemaSpec @Int16 "int16"
  jsonSchemaSpec @Int32 "int32"
  jsonSchemaSpec @Int64 "int64"
  jsonSchemaSpec @Word "word"
  jsonSchemaSpec @Word8 "word8"
  jsonSchemaSpec @Word16 "word16"
  jsonSchemaSpec @Word32 "word32"
  jsonSchemaSpec @Word64 "word64"
  jsonSchemaSpec @(Maybe Text) "maybe-text"
  jsonSchemaSpec @(Either Bool Text) "either-bool-text"
  jsonSchemaSpec @(Either (Either Bool Scientific) Text) "either-either-bool-scientific-text"
  jsonSchemaSpec @[Text] "list-text"
  jsonSchemaSpec @Example "example"
  jsonSchemaSpec @Recursive "recursive"
  describe "JSONSchema" $ do
    genValidSpec @JSONSchema
    it "roundtrips through json and back" $
      forAllValid $ \jsonSchema ->
        -- We use the reencode version to survive the ordering change through map
        let encoded = JSON.encode (jsonSchema :: JSONSchema)
         in case JSON.eitherDecode encoded of
              Left err -> expectationFailure err
              Right decoded ->
                let encodedAgain = JSON.encode (decoded :: JSONSchema)
                 in encodedAgain `shouldBe` encoded

instance GenValid JSONSchema where
  shrinkValid = \case
    AnySchema -> []
    NullSchema -> [AnySchema]
    BoolSchema -> [AnySchema]
    StringSchema -> [AnySchema]
    NumberSchema -> [AnySchema]
    ArraySchema s -> s : (ArraySchema <$> shrinkValid s)
    ObjectSchema os -> filter isValid $ ObjectSchema <$> shrinkValid os
    ValueSchema v -> ValueSchema <$> shrinkValid v
    ChoiceSchema ss -> case ss of
      s :| [] -> [s]
      _ -> ChoiceSchema <$> shrinkValid ss
    CommentSchema k s -> (s :) $ do
      (k', s') <- shrinkValid (k, s)
      pure $ CommentSchema k' s'
    ReferenceSchema k s -> (s :) $ do
      (k', s') <- shrinkValid (k, s)
      pure $ ReferenceSchema k' s'
  genValid = sized $ \n ->
    if n <= 1
      then elements [AnySchema, NullSchema, BoolSchema, StringSchema, NumberSchema]
      else
        oneof
          [ ArraySchema <$> resize (n -1) genValid,
            (ObjectSchema <$> resize (n -1) genValid) `suchThat` isValid,
            do
              (a, b, c) <- genSplit3 (n -1)
              choice1 <- resize a genValid
              choice2 <- resize b genValid
              rest <- resize c genValid
              pure $
                ChoiceSchema $
                  choice1 :| (choice2 : rest),
            do
              (a, b) <- genSplit (n -1)
              (CommentSchema <$> resize a genValid <*> resize b genValid) `suchThat` isValid
          ]

instance GenUnchecked KeyRequirement

instance GenValid KeyRequirement

jsonSchemaSpec :: forall a. (Show a, Eq a, Typeable a, GenValid a, HasCodec a) => FilePath -> Spec
jsonSchemaSpec filePath =
  describe ("jsonSchemaSpec @" <> nameOf @a) $ do
    it "outputs the same schema as before" $
      pureGoldenJSONFile
        ("test_resources/schema/" <> filePath <> ".json")
        (JSON.toJSON (jsonSchemaViaCodec @a))
    it "validates all encoded values" $
      forAllValid $ \(a :: a) ->
        validateAccordingTo (toJSONViaCodec a) (jsonSchemaViaCodec @a) `shouldBe` True