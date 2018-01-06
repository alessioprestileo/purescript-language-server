module LanguageServer.IdePurescript.Tooltips where

import Prelude

import Control.Monad.Aff (Aff)
import Control.Monad.Eff.Class (liftEff)
import Data.Either (either)
import Data.Maybe (Maybe(Nothing, Just), fromMaybe, isJust)
import Data.Newtype (un)
import Data.Nullable (Nullable, toNullable)
import Data.String (drop, length, take)
import Data.String.Regex (match, regex)
import Data.String.Regex.Flags (noFlags)
import IdePurescript.Modules (getQualModule, getUnqualActiveModules)
import IdePurescript.PscIde (getTypeInfo)
import IdePurescript.Tokens (WordRange, identPart, identifierAtPoint)
import LanguageServer.DocumentStore (getDocument)
import LanguageServer.Handlers (TextDocumentPositionParams)
import LanguageServer.IdePurescript.Types (ServerState(..), MainEff)
import LanguageServer.TextDocument (getTextAtRange)
import LanguageServer.Types (DocumentStore, Hover(..), Position(..), Range(..), Settings, TextDocumentIdentifier(..), markedString)
import PscIde.Command as C


moduleBeforePart :: String
moduleBeforePart = """(?:^|[^A-Za-z_.])([A-Z][A-Za-z0-9]*(?:\.[A-Z][A-Za-z0-9]*)*)"""

moduleAfterPart :: String
moduleAfterPart = """([A-Za-z0-9]*)\.""" 

afterPart :: String
afterPart = moduleAfterPart <> identPart -- identPart captures 1

moduleAtPoint :: String -> Int -> Maybe { word :: String, range :: WordRange }
moduleAtPoint line column =
  let textBefore = take column line
      textAfter = drop column line
      beforeRegex = regex (moduleBeforePart <> "$") noFlags
      afterRegex = regex ("^" <> "afterPart") noFlags
      wordRange left right = { left: column - left, right: column + right }
      match' r t = either (const Nothing) (\r' -> match r' t) r
  in
  case match' beforeRegex textBefore, match' afterRegex textAfter of
    Just [_, Just m1], Just [_, Just m2, _] ->
      Just { word : m1 <> m2, range : wordRange (length m1) (length m2) }
    _, _ -> Nothing

getTooltips :: forall eff. DocumentStore -> Settings -> ServerState (MainEff eff) -> TextDocumentPositionParams -> Aff (MainEff eff) (Nullable Hover)
getTooltips docs settings state ({ textDocument, position }) = do
  doc <- liftEff $ getDocument docs (_.uri $ un TextDocumentIdentifier textDocument)
  text <- liftEff $ getTextAtRange doc $ lineRange position
  let { port, modules, conn } = un ServerState state
      char = _.character $ un Position $ position
  case port, identifierAtPoint text char, moduleAtPoint text char of
    Just port', Just { word, qualifier }, _ -> do
      ty <- getTypeInfo port' word modules.main qualifier (getUnqualActiveModules modules $ Just word) (flip getQualModule modules)
      pure $ toNullable $ map (convertInfo word) ty
    Just port', _, Just { word } -> do
      -- ty <- getTypeInfo port' word modules.main qualifier (getUnqualActiveModules modules $ Just word) (flip getQualModule modules)
      -- pure $ toNullable $ map (convertInfo word) ty
      pure $ toNullable $ Just $ Hover {
        contents: markedString "TESTMN"
      , range: toNullable Nothing
      }
    _, _, _-> pure $ toNullable Nothing

  where

  convertInfo word (C.TypeInfo { type', expandedType }) = Hover
    {
      contents: markedString $ compactTypeStr <> 
        if showExpanded then "\n" <> expandedTypeStr else ""
    , range: toNullable $ Nothing -- Just $ Range { start: position, end: position }
    }
    where
      showExpanded = isJust expandedType && (expandedType /= Just type')
      compactTypeStr = word <> " :: " <> type'
      expandedTypeStr = word <> " :: " <> (fromMaybe "" expandedType)

  lineRange (Position { line, character }) =
    Range
      { start: Position
        { line
        , character: 0
        }
      , end: Position
        { line
        , character: character + 100
        }
      }