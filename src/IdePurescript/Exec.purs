module IdePurescript.Exec where

import Prelude

import Control.Alt ((<|>))
import Data.Either (either, Either(..))
import Data.Maybe (fromMaybe, maybe, Maybe(..))
import Effect (Effect)
import Effect.Aff (Aff)
import Effect.Class (liftEffect)
import Foreign.Object as Object
import Node.Path as Path
import Node.Process (getEnv, lookupEnv)
import Node.Which (which')
import PscIde.Server (Executable(..), findBins')

findBins :: forall a. Either a String -> String -> Aff (Array Executable)
findBins pathVar server = do
  env <- liftEffect getEnv
  findBins'
    { pathExt: Nothing
    , path: either (const Nothing) Just pathVar
    , env: either (const Nothing) (Just <<< flip (Object.insert "PATH") env) pathVar
    }
    server

findBinsNoVersion :: forall a. { path :: Maybe String, pathExt :: Maybe String | a } -> String -> Aff (Array Executable)
findBinsNoVersion { path, pathExt } executable = do
  bins <- which' { path, pathExt } executable <|> pure []
  pure $ (\bin -> Executable bin Nothing) <$> bins

getPathVar :: Boolean -> String -> Effect (Either String String)
getPathVar addNpmBin rootDir = do
  processPath <- lookupEnv "PATH"
  pure $ if addNpmBin
    then Right $ addNpmBinPath rootDir processPath
    else Left $ fromMaybe "" processPath

addNpmBinPath :: String -> Maybe String -> String
addNpmBinPath rootDir path =
  Path.concat [ rootDir, "node_modules", ".bin" ] <> (maybe "" (Path.delimiter <> _) path)
