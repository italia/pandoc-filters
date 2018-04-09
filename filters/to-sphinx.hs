{-# LANGUAGE OverloadedStrings #-}
module Main where

import Text.Pandoc
import Text.Pandoc.JSON
import Text.Pandoc.Walk (query, walk)
import qualified Data.Text.IO as T
import Data.Monoid ((<>))
import Options.Applicative
import Control.Monad (sequence_, join)
import Data.Either (fromRight)
import Data.List (intercalate)
import System.Directory (createDirectory,
                         removeDirectoryRecursive,
                         doesFileExist,
                         doesPathExist)
import Control.Applicative ((<$>))
import Control.Monad (when)
import System.FilePath.Posix (dropExtension, addExtension)

main = do
  c <- T.getContents
  c' <- (onBody f . fromRight (Pandoc nullMeta []) . readJSON def) c
  (T.putStr . writeJSON def) c'

onBody :: ([Block] -> IO [Block]) -> Pandoc -> IO Pandoc
onBody f (Pandoc m b) = do
  b' <- f b
  pure (Pandoc m b')

f :: [Block] -> IO [Block]
f d = do
  exists <- doesPathExist "index"  
  when exists (removeDirectoryRecursive "index")
  createDirectory "index"  
  s <- writeSections d
  pure (makeIndex s d)

makeIndex :: [String] -> [Block] -> [Block]
makeIndex s b = getIntro b <> [tableOfContents]
  where tableOfContents = tocTree 2 s
        getIntro = join . fst . breakSections

writeSections :: [Block] -> IO [String]
writeSections = sequence . map writeSection . snd . breakSections

writeSection :: [Block] -> IO String
writeSection s =
  let path = getPath $ head s
  in do
    (Right contents) <- runIO (writeRST def (Pandoc nullMeta s))
    avail <- availablePath path
    T.writeFile avail contents
    pure avail

availablePath :: String -> IO String
availablePath path = do
  (available, c) <- untilM (\ x -> not <$> (doesFileExist $ getPath x)) (\(p, c)-> (p, c+1)) (path, 1)
  pure $ getPath (available, c)
  where getPath (p, 1) = p
        getPath o = addNumber o
        addNumber (p, c) = addExtension (dropExtension p <> "-" <> show c) ".rst"

-- | like `until` but for monadic functions
-- >>> let p a = Just (a > 3)
-- >>> untilM p (+1) 0
-- Just 4
untilM :: Monad m => (a -> m Bool) -> (a -> a) -> a -> m a
untilM p f i = do
  r <- p i
  if r then pure i else untilM p f (f i)

breakSections body = (intro, sections)
  where intro = take 1 broken
        sections = drop 1 broken
        broken = multiBreak (isHeading (level body)) body

-- | if we have only one header 1 break by header 2 and so on
level :: [Block] -> Int
level body = head $ filter hasSeveral [1, 2, 3, 4, 5]
  where hasSeveral l = (length $ query (collectHeading l) body) > 1
        collectHeading l i = if isHeading l i then [i] else []

-- | Multiple version of break, like a `split` that keeps the delimiter
-- >>> multiBreak (==' ') "bla bla bla b"
-- ["bla"," bla"," bla"," b"]
multiBreak :: (a -> Bool) -> [a] -> [[a]]
multiBreak p [] = []
multiBreak p l@(h:t)
  | p h       = (h : t1) : multiBreak p t2
  | otherwise = l1 : multiBreak p l2
  where (t1, t2) = break p t
        (l1, l2) = break p l

{-

.. toctree::
   :maxdepth: 2
   :caption: Indice dei contenuti

   index/che-cos-e-docs-italia.rst
   index/starter-kit.rst

-}
tocTree :: Int -> [String] -> Block
tocTree depth paths = RawBlock "rst" $
           ".. toctree::" <>
           "\n  :maxdepth: " <> show depth <>
           "\n  :caption: Indice dei contenuti" <>
           "\n" <>
           concatMap (\x -> "\n  "<>x) paths

-- | get the path corresponding to some heading
-- >>> getPath (Header 2 ("", [], []) [Str "my section accénted"])
-- "index/my-section-accénted.rst"
getPath :: Block -> String
getPath (Header _  _ i) = "index/" <> adapt (foldl j "" $ walk simplify' i) <> ".rst"
  where j s1 (Str s2) = s1 <> s2
        adapt = map replace . limit -- adapt for the file system
        limit = take 50 -- file names cannot be too long
        replace '/' = '-'
        replace o = o

simplify' = concatMap simplify

simplify :: Inline -> [Inline]
simplify (Emph i) = i
simplify (Strong i) = i
simplify Space = [Str "-"]
simplify i = [i]

isHeading :: Int -> Block -> Bool
isHeading a (Header b _ _) = a == b
isHeading _ _ = False
