
{-# LANGUAGE BangPatterns #-}

module Main where

import           Data.Char
import           Data.List                             (intercalate, nub, sort,
                                                        sortBy)
import           Data.Maybe
import           Data.MemoTrie
import           Data.Traversable                      (traverse)
import           Distribution.ModuleName               (components)
import qualified Distribution.PackageDescription       as PD
import qualified Distribution.PackageDescription.Parse as PDP
import           Distribution.Verbosity                (normal)
import           Language.Haskell.Interpreter
import           System.Environment
import           System.IO
import           System.IO.Unsafe
import           System.Process
import           Text.Regex

type Identifier = String

------------------------------------------------------------------------------------------

main :: IO ()
main = do
    args <- getArgs
    runStd args

runStd :: [FilePath] -> IO ()
runStd = runFilter stdin stdout

runFilter :: Handle -> Handle -> [FilePath] -> IO ()
runFilter inf outf args = hGetContents inf >>= run args >>= hPutStr outf

------------------------------------------------------------------------------------------

-- |
-- Given a list of cabal files, process input by replacing all text on the form
-- @[foo] with [`foo`][foo], replacing @@@hslinks@@@ with an index on the form:
--
-- [foo]:         prefix/Module-With-Foo.html#v:foo
-- [Foo]:         prefix/Module-With-Foo.html#t:Foo
--
-- etc.
--
run :: [FilePath] -> String -> IO String
run args input = do
    !modNames <- visibleModsInCabals args

    let ids = nub $ fmap getId $ allMatches idExpr input
    let !toLinks = idToLink modNames
    let links = map toLinks ids
    let index = intercalate "\n" links

    return $ subElems $ subIndex index input
    where
        idChars   = "[^]]+"
        idExpr    = mkRegex $ "@\\[(" ++ idChars ++ ")\\]"
        indexExpr = mkRegex $ "@@@hslinks@@@"
        getId     = head . snd



        subElems a   = subRegex idExpr    a "[`\\1`][\\1]"
        subIndex i a = subRegex indexExpr a i

        -- FIXME
        kPrefix = "/docs/api/"

        idToLink :: [ModuleName] -> Identifier -> String
        idToLink sources ident = do
            let vOrT = if isUpper (head ident) then "t" else "v"
            -- TODO
            -- TODO This should be optionalg
            let package = "music-score"
            case whichModule sources (wrapOp ident) of
                Left e -> "\n<!-- Unknown: " ++ ident ++ " " ++ e ++ "-->\n"
                Right modName -> ""
                    ++ "[" ++ ident ++ "]: " ++ kPrefix ++ package ++ "/"
                    ++ replace '.' '-' modName ++ ".html#" ++ vOrT ++ ":" ++ handleOp ident ++ ""

wrapOp :: Identifier -> Identifier
wrapOp []     = []
wrapOp as@(x:_)
    | isAlphaNum x = as
    | otherwise    = "(" ++ as ++ ")"

handleOp :: Identifier -> Identifier
handleOp []     = []
handleOp as@(x:_)
    | isAlphaNum x = as
    | otherwise    = escapeOp as

escapeOp = concatMap (\c -> "-" ++ show (ord c) ++ "-")


allMatches :: Regex -> String -> [(String, [String])]
allMatches reg str = case matchRegexAll reg str of
    Nothing                           -> []
    Just (before, match, after, subs) -> (match, subs) : allMatches reg after


-----------------------------------------------------------------------------------------

-- whichModule, visibleModsInCabals

-- Given a set of modules, find the topmost module in which an identifier appears
-- A module is considered above another if it has fewer dots in its name. If the number of
-- dots are equal, use lexiographic order.
whichModule :: [ModuleName] -> Identifier -> Either String ModuleName
whichModule modNames ident = eitherMaybe ("No such identifier: " ++ ident)
    $ fmap (listToMaybe . sortBy bottomMost) modsWithIdent
    where
        mods = modsNamed modNames
        -- modules containing the identifier
        modsWithIdent = fmap (hasIdent ident) mods

modsNamed :: [ModuleName] -> Either String [(ModuleName, [Identifier])]
modsNamed = traverse modNamed

modNamed :: ModuleName -> Either String (ModuleName, [Identifier])
modNamed = modNamed'
modNamed' n = case identifiers n of {
    Left e    -> Left e ;
    Right ids -> Right (n, ids) ;
    }

hasIdent :: Identifier -> [(ModuleName, [Identifier])] -> [ModuleName]
hasIdent ident = fmap fst . filter (\(n,ids) -> ident `elem` ids)

-- | Get all the identifiers of a module
identifiers :: ModuleName -> Either String [Identifier]
identifiers = unsafePerformIO . identifiers'

identifiers' :: ModuleName -> IO (Either String [Identifier])
identifiers' modName = fmap getElemNames $ runInterpreter $ getModuleExports modName
    where
        getElemNames = either (Left . getError) Right . fmap (concatMap getModuleElem)
        getError = show

-- | Get all identifiers in a module element (names, class members, data constructors)
getModuleElem :: ModuleElem -> [Identifier]
getModuleElem (Fun a)      = [a]
getModuleElem (Class a as) = a:as
getModuleElem (Data a as)  = a:as

modsInDir :: FilePath -> IO [ModuleName]
modsInDir dir = do
    dirList <- readProcess "find" [dir, "-type", "f", "-name", "*.hs"] ""
    let dirs = lines dirList
    let mods = fmap (pathToModName . dropBaseDir) dirs
    return mods
    where
        dropBaseDir   = drop (length dir)
        pathToModName = replace '/' '.' . dropWhile (not . isUpper) . dropLast 3

visibleModsInCabals :: [FilePath] -> IO [ModuleName]
visibleModsInCabals = fmap concat . mapM visibleModsInCabal

visibleModsInCabal :: FilePath -> IO [ModuleName]
visibleModsInCabal path = do
    packageDesc <- PDP.readPackageDescription normal path
    case PD.condLibrary packageDesc of
        Nothing -> return []
        Just libTree -> return (fmap unModName $ PD.exposedModules $ foldCondTree libTree)
        where
            unModName = intercalate "." . components
            foldCondTree (PD.CondNode x c comp) = x -- TODO subtrees

bottomMost :: ModuleName -> ModuleName -> Ordering
bottomMost a b = case level a `compare` level b of
    LT -> GT
    EQ -> a `compare` b
    GT -> LT
    where
        level = length . filter (== '.')

-----------------------------------------------------------------------------------------

eitherMaybe :: e -> Either e (Maybe a) -> Either e a
eitherMaybe e' = go
    where
        go (Left  e)         = Left e
        go (Right Nothing)   = Left e'
        go (Right (Just a))  = Right a

-- | @replace x y xs@ replaces all instances of a @x@ in a list @xs@ with @y@.
replace :: Eq a => a -> a -> [a] -> [a]
replace x y = map $ \z -> if z == x then y else z

takeLast :: Int -> [a] -> [a]
takeLast n = reverse . take n . reverse

dropLast :: Int -> [a] -> [a]
dropLast n = reverse . drop n . reverse





