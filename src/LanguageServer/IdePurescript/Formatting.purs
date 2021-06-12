module LanguageServer.IdePurescript.Formatting where

import Prelude

import Data.Either (Either(..))
import Data.Foldable (length)
import Data.Maybe (Maybe(..))
import Data.String.Utils (lines)
import Effect (Effect)
import Effect.Aff (Aff, attempt, makeAff)
import Effect.Class (liftEffect)
import Effect.Exception (catchException, error)
import Effect.Ref as Ref
import Foreign (unsafeToForeign)
import Foreign as Foreign
import IdePurescript.Build (Command(..), spawn)
import IdePurescript.PscIdeServer (ErrorLevel(..), Notify)
import LanguageServer.DocumentStore (getDocument)
import LanguageServer.Handlers (DocumentFormattingParams)
import LanguageServer.IdePurescript.Config as Config
import LanguageServer.IdePurescript.Types (ServerState(..))
import LanguageServer.TextDocument (getText)
import LanguageServer.Types (DocumentStore, Position(..), Range(..), Settings, TextDocumentIdentifier(..), TextEdit(..))
import Node.ChildProcess as CP
import Node.Encoding (Encoding(..))
import Node.Encoding as Encoding
import Node.Stream as S

getFormattedDocument :: Notify -> DocumentStore -> Settings -> ServerState -> DocumentFormattingParams -> Aff (Array TextEdit)
getFormattedDocument logCb docs settings serverState { textDocument: TextDocumentIdentifier textDocId } = do
  text <- liftEffect $ getText =<< getDocument docs textDocId.uri
  newTextEither <- attempt $ formatWithPurty logCb settings serverState text

  case newTextEither of
    Left err -> liftEffect (logCb Error $ show err) $> []
    Right "" -> pure []
    Right newText -> pure [ mkTextEdit text newText ]

formatWithPurty :: Notify -> Settings -> ServerState -> String -> Aff String
formatWithPurty _ settings state text = do
  case state of 
    ServerState { root: Just directory } -> do
      makeAff $ \cb -> do
        let succ = cb <<< Right
            err = cb <<< Left
        cp <- spawn { command: Command "purty" [ "format", "-" ], directory, useNpmDir: Config.addNpmPath settings }
        CP.onError cp (err <<< CP.toStandardError)
        result <- Ref.new ""
        let res :: String -> Effect Unit
            res s = Ref.modify_ (_ <> s) result

        catchException err $ S.onDataString (CP.stderr cp) Encoding.UTF8 $ err <<< error
        catchException err $ S.onDataString (CP.stdout cp) Encoding.UTF8 res

        CP.onClose cp \exit -> case exit of
          CP.Normally n | n == 0 || n == 1 ->
            Ref.read result >>= succ
          _ -> err $ error "purty process exited abnormally"
        
        when (not $ Foreign.isUndefined $ unsafeToForeign $ CP.pid cp) do
          catchException err $ void $ S.writeString (CP.stdin cp) UTF8 text (pure unit)
          catchException err$ S.end (CP.stdin cp) (pure unit)


        pure mempty
    _ -> pure ""

mkTextEdit :: String -> String -> TextEdit
mkTextEdit oldText text = TextEdit { range, newText: text }
  where
  range =
    Range
      { start: Position { line: 0, character: 0 }
      , end: Position { line: (length $ lines oldText) + 1, character: 0 }
      }
