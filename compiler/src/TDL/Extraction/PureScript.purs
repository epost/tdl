module TDL.Extraction.PureScript
  ( pursTypeName
  , pursEq
  , pursSerialize
  , pursModule
  , pursDeclaration
  ) where

import Data.Array as Array
import Data.Foldable (fold, foldMap, foldr)
import Data.String as String
import Data.Tuple (Tuple)
import Data.Tuple.Nested ((/\))
import Prelude
import TDL.LambdaCalculus (etaExpandType)
import TDL.Syntax (Declaration(..), Kind(..), Module(..), PrimType(..), Type(..))
import Partial.Unsafe (unsafeCrashWith)

pursKindName :: Kind -> String
pursKindName SeriKind = "Type"
pursKindName (ArrowKind k i) = "(" <> pursKindName k <> " " <> pursKindName i <> ")"

pursTypeName :: Type -> String
pursTypeName (NamedType n) = n
pursTypeName (AppliedType t u) = "(" <> pursTypeName t <> " " <> pursTypeName u <> ")"
pursTypeName (PrimType BoolType)  = "Boolean"
pursTypeName (PrimType I32Type)   = "Int"
pursTypeName (PrimType F64Type)   = "Number"
pursTypeName (PrimType TextType)  = "String"
pursTypeName (PrimType ArrayType) = "Array"
pursTypeName (PrimType BytesType) = "TDLSUPPORT.ByteString"
pursTypeName (ProductType ts) = "{" <> String.joinWith ", " entries <> "}"
  where entries = map (\(k /\ t) -> k <> " :: " <> pursTypeName t) ts
pursTypeName (SumType []) = "TDLSUPPORT.Void"
pursTypeName (SumType _) = unsafeCrashWith "pursTypeName: SumType _"

pursEq :: Type -> String
pursEq t@(NamedType _)       = pursNominalEq t
pursEq (AppliedType t u)     = "(" <> pursEq t <> " " <> pursEq u <> ")"
pursEq t@(PrimType BoolType)  = pursNominalEq t
pursEq t@(PrimType I32Type)   = pursNominalEq t
pursEq t@(PrimType F64Type)   = pursNominalEq t
pursEq t@(PrimType TextType)  = pursNominalEq t
pursEq (PrimType ArrayType)   = "TDLSUPPORT.eqArray"
pursEq t@(PrimType BytesType) = pursNominalEq t
pursEq (ProductType ts) =
  "(\\tdl__a tdl__b -> " <> foldr (\a b -> a <> " TDLSUPPORT.&& " <> b) "true" entries <> ")"
  where entries = map entry ts
        entry (k /\ t) = "(" <> pursEq t <> " tdl__a." <> k <> " tdl__b." <> k <> ")"
pursEq (SumType ts) =
  "(\\tdl__a tdl__b -> case tdl__a, tdl__b of\n"
  <> indent (fold (Array.mapWithIndex entry ts)) <> "\n"
  <> "  _, _ -> false)"
  where entry i (_ /\ t) = path i "tdl__c" <> ", " <> path i "tdl__d"
                           <> " -> " <> pursEq t <> " tdl__c tdl__d\n"
        path n v | n <= 0    = "TDLSUPPORT.Left " <> v
                 | otherwise = "TDLSUPPORT.Right (" <> path (n - 1) v <> ")"

pursNominalEq :: Type -> String
pursNominalEq t = "(TDLSUPPORT.eq :: " <> n <> " -> " <> n <> " -> Boolean)"
  where n = pursTypeName t

pursSerialize :: Type -> String
pursSerialize (NamedType n) = "intermediateFrom" <> n
pursSerialize (AppliedType t u) = "(" <> pursSerialize t <> " " <> pursSerialize u <> ")"
pursSerialize (PrimType BoolType)  = "TDLSUPPORT.fromBool"
pursSerialize (PrimType I32Type)   = "TDLSUPPORT.fromI32"
pursSerialize (PrimType F64Type)   = "TDLSUPPORT.fromF64"
pursSerialize (PrimType TextType)  = "TDLSUPPORT.fromText"
pursSerialize (PrimType ArrayType) = "TDLSUPPORT.fromArray"
pursSerialize (PrimType BytesType) = "TDLSUPPORT.fromBytes"
pursSerialize (ProductType ts) =
  "(\\tdl__r -> TDLSUPPORT.fromProduct [" <> String.joinWith ", " entries <> "])"
  where entries = map entry ts
        entry (k /\ t) = "{ k: " <> show k <>
                         ", v: " <> pursSerialize t <> " tdl__r." <> k <> " " <>
                         "}"
pursSerialize (SumType []) = "TDLSUPPORT.absurd"
pursSerialize (SumType _) = unsafeCrashWith "pursSerialize: SumType _"

pursDeserialize :: Type -> String
pursDeserialize (NamedType n) = "intermediateTo" <> n
pursDeserialize (AppliedType t u) = "(" <> pursDeserialize t <> " " <> pursDeserialize u <> ")"
pursDeserialize (PrimType BoolType)  = "TDLSUPPORT.toBool"
pursDeserialize (PrimType I32Type)   = "TDLSUPPORT.toI32"
pursDeserialize (PrimType F64Type)   = "TDLSUPPORT.toF64"
pursDeserialize (PrimType TextType)  = "TDLSUPPORT.toText"
pursDeserialize (PrimType ArrayType) = "TDLSUPPORT.toArray"
pursDeserialize (PrimType BytesType) = "TDLSUPPORT.toBytes"
pursDeserialize (ProductType ts) =
  "(\\tdl__r -> "
  <> "TDLSUPPORT.toProduct tdl__r"
  <> " TDLSUPPORT.>>= \\tdl__r' ->\n"
  <> record <> ")"
  where
    record
      | Array.length ts == 0 = "  TDLSUPPORT.pure {}"
      | otherwise = indent (
            "{" <> String.joinWith ", " (map (\(k /\ _) -> k <> ": _") ts) <> "}\n"
            <> "TDLSUPPORT.<$> "
            <> String.joinWith "\nTDLSUPPORT.<*> " (map entry ts)
          )
    entry (k /\ t) =
      "(" <> pursDeserialize t <> " TDLSUPPORT.=<<" <>
      " TDLSUPPORT.maybe (TDLSUPPORT.Left \"Key not present.\")" <>
      " TDLSUPPORT.Right" <>
      " (TDLSUPPORT.lookup " <> show k <> " tdl__r')" <>
      ")"
pursDeserialize (SumType []) =
  "(\\_ -> TDLSUPPORT.Left " <> show "Unknown sum discriminator." <> ")"
pursDeserialize (SumType _) = unsafeCrashWith "pursDeserialize: SumType _"

pursHash :: Type -> String
pursHash t = "(TDLSUPPORT.hash " <> pursSerialize t <> ")"

pursModule :: Module -> String
pursModule (Module n _ m) =
     "module " <> n <> " where\n"
  <> "import TDL.Support as TDLSUPPORT\n"
  <> "import TDL.Intermediate as TDLSUPPORT\n"
  <> foldMap pursDeclaration m

pursDeclaration :: Declaration -> String
pursDeclaration (TypeDeclaration n _ k t) =
  case t of
    SumType [] -> pursTypeDeclaration n k t
    SumType ts -> pursSumDeclaration n ts
    _ -> pursTypeDeclaration n k t
pursDeclaration (ServiceDeclaration n _ f t) =
  "define" <> n
  <> " :: forall tdl__e"
  <> "  . (" <> pursTypeName f <> " -> TDLSUPPORT.Aff tdl__e " <> pursTypeName t <> ")"
  <> " -> TDLSUPPORT.Service tdl__e\n"
  <> "define" <> n <> " = "
  <> "TDLSUPPORT.service " <> pursDeserialize f <> " "
                           <> pursSerialize t <> " "
                           <> show n <> "\n"

  <> "call" <> n
  <> " :: forall tdl__e"
  <> "  . String"
  <> " -> " <> pursTypeName f
  <> " -> TDLSUPPORT.Aff (ajax :: TDLSUPPORT.AJAX | tdl__e) " <> pursTypeName t <> "\n"
  <> "call" <> n <> " = "
  <> "TDLSUPPORT.call " <> pursSerialize f <> " "
                        <> pursDeserialize t <> " "
                        <> show n <> "\n"

pursSumDeclaration :: String -> Array (Tuple String Type) -> String
pursSumDeclaration n ts =
  adt
  <> eqInstance
  <> serializeFunction
  <> deserializeFunction
  where
    adt = "data " <> n <> "\n  = " <> String.joinWith "\n  | " (map adtEntry ts) <> "\n"
    adtEntry (k /\ t) = n <> "_" <> k <> " " <> pursTypeName t

    eqInstance =
         "instance eq" <> n <> " :: TDLSUPPORT.Eq " <> n <> " where\n"
      <> foldMap eqMethod ts
    eqMethod (k /\ t) =
      "  eq (" <> n <> "_" <> k <> " tdl__a) = case _ of\n"
      <> "    (" <> n <> "_" <> k <> " tdl__b) ->\n"
      <> indent (indent (indent ("(" <> pursEq t <> ") tdl__a tdl__b"))) <> "\n"
      <> "    _ -> false\n"

    serializeFunction =
         "intermediateFrom" <> n <> " :: " <> n <> " -> TDLSUPPORT.Intermediate\n"
      <> fold (map serializeCase ts)
    serializeCase (k /\ t) =
         "intermediateFrom" <> n <> " (" <> n <> "_" <> k <> " tdl__a) =\n"
      <> indent ("TDLSUPPORT.fromSum "
                    <> show k <> " "
                    <> pursSerialize t <> " "
                    <> "tdl__a") <> "\n"

    deserializeFunction =
         "intermediateTo" <> n
      <> " :: TDLSUPPORT.Intermediate -> TDLSUPPORT.Either String " <> n <> "\n"
      <> "intermediateTo" <> n <> " = TDLSUPPORT.toSum TDLSUPPORT.>=> case _ of\n"
      <> fold (map deserializeCase ts)
      <> "  {d: _} -> TDLSUPPORT.Left " <> show "Unknown sum discriminator." <> "\n"
    deserializeCase (k /\ t) =
         "  {d: " <> show k <> ", x: tdl__x} ->\n"
      <> indent (indent (pursDeserialize t)) <> " tdl__x "
      <> "TDLSUPPORT.<#> " <> n <> "_" <> k <> "\n"

pursTypeDeclaration :: String -> Kind -> Type -> String
pursTypeDeclaration n k t =
  case etaExpandType k t of
    {params, type: t'} ->
      let params' = map (\(p /\ k) -> " (" <> p <> " :: " <> pursKindName k <> ")") params in
         "newtype " <> n <> fold params' <> " = " <> n <> " " <> pursTypeName t' <> "\n"
      <> (if k == SeriKind then eqInstance          else "")
      <> (if k == SeriKind then serializeFunction   else "")
      <> (if k == SeriKind then deserializeFunction else "")
      <> (if k == SeriKind then hashFunction        else "")
  where
    eqInstance =
         "instance eq" <> n <> " :: TDLSUPPORT.Eq " <> n <> " where\n"
      <> "  eq (" <> n <> " tdl__a) (" <> n <> " tdl__b) =\n"
      <> indent (indent ("(" <> pursEq t <> ") tdl__a tdl__b")) <> "\n"

    serializeFunction =
         "intermediateFrom" <> n <> " :: " <> n <> " -> TDLSUPPORT.Intermediate\n"
      <> "intermediateFrom" <> n <> " (" <> n <> " tdl__a) =\n"
      <> indent (pursSerialize t <> " tdl__a") <> "\n"

    deserializeFunction =
         "intermediateTo" <> n
      <> " :: TDLSUPPORT.Intermediate -> TDLSUPPORT.Either String " <> n <> "\n"
      <> "intermediateTo" <> n <> " =\n"
      <> indent (pursDeserialize t) <> "\n"
      <> "  TDLSUPPORT.>>> TDLSUPPORT.map " <> n <> "\n"

    hashFunction =
         "hash" <> n <> " :: " <> n <> " -> TDLSUPPORT.ByteString\n"
      <> "hash" <> n <> " =\n"
      <> "  " <> pursHash (NamedType n) <> "\n"

indent :: String -> String
indent =
  String.split (String.Pattern "\n")
  >>> map ("  " <> _)
  >>> String.joinWith "\n"
