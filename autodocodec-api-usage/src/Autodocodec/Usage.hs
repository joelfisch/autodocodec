{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TypeApplications #-}

-- This module contains so-called "API Usage" Tests.
-- This means that this module tests that its usage of the API is still supported.
-- Consequentially, we must be careful about refactoring any code in this module.
module Autodocodec.Usage where

import Autodocodec
import Control.Applicative
import Data.Aeson (FromJSON (..), ToJSON (..))
import qualified Data.Aeson as JSON
import Data.GenValidity
import Data.GenValidity.Aeson ()
import Data.GenValidity.Scientific ()
import Data.GenValidity.Text ()
import Data.Int
import Data.Maybe
import Data.Scientific
import Data.Text (Text)
import qualified Data.Text.Lazy as LT
import Data.Word
import GHC.Generics (Generic)
import Test.QuickCheck

data Fruit
  = Apple
  | Orange
  | Banana
  | Melon
  deriving (Show, Eq, Generic, Enum, Bounded)

instance Validity Fruit

instance GenValid Fruit where
  genValid = genValidStructurally
  shrinkValid = shrinkValidStructurally

instance HasCodec Fruit where
  codec = shownBoundedEnumCodec

instance FromJSON Fruit

instance ToJSON Fruit

data Example = Example
  { exampleText :: !Text,
    exampleBool :: !Bool,
    exampleRequiredMaybe :: !(Maybe Text),
    exampleOptional :: !(Maybe Text),
    exampleFruit :: !Fruit
  }
  deriving (Show, Eq, Generic)

instance Validity Example

instance GenValid Example where
  genValid = genValidStructurally
  shrinkValid = shrinkValidStructurally

instance HasCodec Example where
  codec =
    object "Example" $
      Example
        <$> requiredField "text" .= exampleText
        <*> requiredField "bool" .= exampleBool
        <*> requiredField "maybe" .= exampleRequiredMaybe
        <*> optionalField "optional" .= exampleOptional
        <*> requiredField "fruit" .= exampleFruit

instance ToJSON Example where
  toJSON Example {..} =
    JSON.object $
      concat
        [ [ "text" JSON..= exampleText,
            "bool" JSON..= exampleBool,
            "maybe" JSON..= exampleRequiredMaybe,
            "fruit" JSON..= exampleFruit
          ],
          ["optional" JSON..= opt | opt <- maybeToList exampleOptional]
        ]

instance FromJSON Example where
  parseJSON = JSON.withObject "Example" $ \o ->
    Example
      <$> o JSON..: "text"
      <*> o JSON..: "bool"
      <*> o JSON..: "maybe"
      <*> o JSON..:? "optional"
      <*> o JSON..: "fruit"

-- Recursive type
data Recursive
  = Base Int
  | Recurse Recursive
  deriving (Show, Eq, Generic)

instance Validity Recursive

instance GenValid Recursive where
  shrinkValid = \case
    Base i -> Base <$> shrinkValid i
    Recurse r -> [r]
  genValid = sized $ \n -> case n of
    0 -> Base <$> genValid
    _ ->
      oneof
        [ Base <$> genValid,
          Recurse <$> resize (n -1) genValid
        ]

instance ToJSON Recursive where
  toJSON = \case
    Base n -> toJSON n
    Recurse r -> JSON.object ["recurse" JSON..= r]

instance FromJSON Recursive where
  parseJSON v =
    JSON.withObject "Base" (\o -> Base <$> o JSON..: "recurse") v
      <|> (Recurse <$> JSON.parseJSON v)

instance HasCodec Recursive where
  codec =
    let f = \case
          Left i -> Base i
          Right r -> Recurse r
        g = \case
          Base i -> Left i
          Recurse r -> Right r
     in bimapCodec f g $
          eitherCodec
            (codec @Int)
            (object "Recurse" $ requiredField "recurse")