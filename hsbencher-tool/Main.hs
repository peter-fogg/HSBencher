{-# LANGUAGE DeriveDataTypeable #-} 

module Main where

-- import Control.Monad.Reader
-- import qualified Data.Map as M
-- import Data.Time.Clock (getCurrentTime, diffUTCTime)
-- import Data.Time.Clock.POSIX (utcTimeToPOSIXSeconds)
-- import Data.Monoid
-- import Data.Dynamic
-- import GHC.Conc (getNumProcessors)
import System.Environment (getArgs, getEnv, getEnvironment)
import System.Console.GetOpt (getOpt', ArgOrder(Permute), OptDescr(Option), ArgDescr(..), usageInfo)
-- import System.IO (Handle, hPutStrLn, stderr, openFile, hClose, hGetContents, hIsEOF, hGetLine,
--                   IOMode(..), BufferMode(..), hSetBuffering)
-- import qualified System.IO.Streams as Strm
-- import qualified System.IO.Streams.Concurrent as Strm
-- import qualified System.IO.Streams.Process as Strm
-- import qualified System.IO.Streams.Combinators as Strm

import Data.List (isInfixOf, isPrefixOf, isSuffixOf, transpose, intersperse)
import Data.List.Split (splitOn)
import Data.String.Utils (strip)

import Control.Monad (unless,when)
import System.Exit (exitFailure, exitSuccess)
import System.IO (hPutStrLn)

-- import HSBencher.Types
-- import HSBencher.Internal.Utils
-- import HSBencher.Methods.Builtin
-- import HSBencher.Internal.MeasureProcess

import HSBencher.Internal.Fusion (init,getSomething,getWithSQLQuery,ColData(..),FTValue(..))

-- Exceptions
import Control.Exception
import Data.Typeable

-- SQL Parsing
import qualified Language.SQL.SimpleSQL.Parser as SQL
import qualified Language.SQL.SimpleSQL.Pretty as SQL
import qualified Language.SQL.SimpleSQL.Syntax as SQL


import qualified Prelude as P
import Prelude hiding (init) 
---------------------------------------------------------------------------
--



{- DEVLOG

   * ISSUES 

     - Wizard is not implemented!
     - Guided CSV generation is not implemented
     
 
   * PLANS and Thoughts 

  
     - SQL Queries:
     Need to read up on what limitations the FT api put on these Queries.

     One thing I noticed is that the query takes the shape:
     SELECT xxxx FROM table_id WHERE yyy
     here table_id is some 'strange' unique identifier string that maybe the user does
     not really want to care about. 

     - Environment variables:
     Allow user to have secret and id as env variables.


   *Example usage


      -- Should add --raw to each of these for output 
      -- QUERY 1
     /hsbencher do --secret=MQ72ZWDde_1e1ihI5YE9YlEi --id=925399326325-6dir7re3ik7686p6v3kkfkf1kj0ec7ck.apps.googleuserconteom --table=Dynaprof_Benchmarks --query="SELECT * FROM FT WHERE GIT_DEPTH = 445"

     -- QUERY 2 
     hsbencher do --secret=MQ72ZWDde_1e1ihI5YE9YlEi --id=925399326325-6dir7re3ik7686p6v3kkfkf1kj0ec7ck.apps.googleusercontent.com --table=Dynaprof_Benchmarks --query="SELECT 'MEDIANTIME' FROM FT WHERE GIT_DEPTH = 445 AND PROGNAME = 'h264ref-9.3'"

     -- QUERY 3
     hsbencher do --secret=MQ72ZWDde_1e1ihI5YE9YlEi --id=925399326325-6dir7re3ik7686p6v3kkfkf1kj0ec7ck.apps.googleusercontent.com --table=Dynaprof_Benchmarks --query="SELECT 'PROGNAME', 'VARIANT', 'MEDIANTIME', 'HOSTNAME' FROM FT WHERE GIT_DEPTH = 445 AND PROGNAME = 'h264ref-9.3'"
  

     -- Heres a good query
     hsbencher do --secret=MQ72ZWDde_1e1ihI5YE9YlEi --id=925399326325-6dir7re3ik7686p6v3kkfkf1kj0ec7ck.apps.googleusercontent.com --table=Dynaprof_Benchmarks --query="SELECT VARIANT, AVERAGE('MEDIANTIME') FROM FT WHERE GIT_DEPTH = 445 AND PROGNAME = 'h264ref-9.3' AND HOSTNAME = 'xmen' GROUP BY VARIANT" --raw



     -- here with filtering and splitting! 
     hsbencher do --secret=MQ72ZWDde_1e1ihI5YE9YlEi --id=925399326325-6dir7re3ik7686p6v3kkfkf1kj0ec7ck.apps.googleusercontent.com --table=Dynaprof_Benchmarks --query="SELECT VARIANT, AVERAGE('MEDIANTIME') FROM FT WHERE GIT_DEPTH = 445 AND PROGNAME = 'h264ref-9.3' AND HOSTNAME = 'xmen' GROUP BY VARIANT" --raw --floc="Column 0" --fby="Prefix" --fstr="resampling" --sloc="Column 0" --sby="_"




     The FROM field allows the text "FT" which is translated into the fusiontable id
     given we know the human readable name as passed into wiht --table=name

-} 




---------------------------------------------------------------------------
-- //                                                                 \\ --
---------------------------------------------------------------------------

-- | Command line flags to the benchmarking executable.
data Flag = ShowHelp | ShowVersion
          | GoogleSecret String | GoogleID String
          | FTName String
          | FTQuery String
-- CSV Conversion related Flags 
          | Wizard  -- Do your best
          | RawCSV  -- Make no effort
            
          -- finer grained control 
          | BenchName String      -- commaseparated list that specifies the "Name" 
          | BenchVariation String -- for example "Threads"
          | BenchData String      -- What goes in the fields

-- All this needs to be cleaned up when there is time to really understand this Flag stuff 
-- Simple filters that are applied after the pulldown (refinement over the limited SQL FT capabilites)
          | FilterLoc String      -- Readable as LocationSpec
          | FilterBy  String      -- Readable as FilterSpec 
          | FilterStr String      -- Just a string 
-- Split up
          | SplitLoc String       -- Readable as LocationSpec
          | SplitBy  String       -- a character to split by
-- GroupBy
-- GroupBy  String       -- Readable as LocationSpec

            
            
  deriving (Eq,Ord,Show,Read)

-- | Current run mode of the tool 
data Mode = Upload | Download
          deriving (Eq,Ord,Show,Read)

-- | Exceptions that may occur
data Error
  = FlagsNotValidE String
    deriving (Show, Typeable) 

instance Exception Error 


data LocationSpec = Row Int | Column Int 
                  deriving (Eq, Ord, Show, Read )

data FilterSpec = Prefix | Infix | Suffix
                deriving (Eq, Ord, Show, Read )


-- | List of valid operation modes of the hsbencher tool
valid_modes :: [String]
valid_modes = [ "upload", "download" ]

-- | Command line options.
core_cli_options :: [OptDescr Flag]
core_cli_options = 
     [ Option ['h'] ["help"] (NoArg ShowHelp)
        "Show this help message and exit."
     , Option []     ["secret"] (ReqArg GoogleSecret "String") "Google Secret"
     , Option []     ["id"]     (ReqArg GoogleID "String")     "Google ID"
     , Option []     ["table"]  (ReqArg FTName "String")       "Name of FusionTable"
     , Option ['q']  ["query"]  (ReqArg FTQuery "String")      "A SQL style query"
     , Option ['w']  ["Wizard"] (NoArg Wizard)                 "Generate a decent CSV file with no user guidance"
     , Option ['n']  ["name"]   (ReqArg BenchName "String")    "For example VARIANT"
     , Option ['v']  ["variation"] (ReqArg BenchVariation "String") "For example NUM_THREADS"
     , Option ['d']  ["data"]   (ReqArg BenchData "String")    "For example MEDIANTIME"
     , Option []     ["raw"]    (NoArg RawCSV)                 "Effortless CSV" 

-- refined filtering, splitting and grouping that is applied to the resulting CSV
     , Option []     ["floc"] (ReqArg FilterLoc "String")      "Row <N> or Column <N>"
     , Option []     ["fby"]  (ReqArg FilterBy  "String")      "Prefix or Infix or Suffix"
     , Option []     ["fstr"] (ReqArg FilterStr "String")      "String to match against"

     , Option []     ["sloc"] (ReqArg SplitLoc "String")       "Row <N> or Column <N>"
     , Option []     ["sby"]  (ReqArg SplitBy  "String")       "for example _ or -"

--      , Option []     ["gby"]  (ReqArg GroupBy  "String")       "Restructure CSV by creating groups **Warning increases dimensionality!**" 
     ]





-- | Multiple lines of usage info help docs.
fullUsageInfo :: String
fullUsageInfo = usageInfo docs core_cli_options
 where 
  docs = "USAGE: hsbencher [mode] <flags> ...\n"++
         "\nValid modes: "++(unwords valid_modes)++
         "\n\nhsbencher-tool general options: \n"
--   ++ generalUsageStr

-- | Is a valid mode requested, if so turn it into a Mode.
--   a uniquely identifying infix of the mode is all that needs
--   to be recognized. So "up" and "do" are valid. 
resolveMode :: String -> Mode
resolveMode md = 
 case filter (isInfixOf md) valid_modes of
   ["download"] -> Download
   ["upload"]   -> Upload 
   []  -> error $ "Unknown mode for hsbencher tool: "++md
   ls  -> error $ "Ambiguous mode for hsbencher tool: "++md++", matches: "++unwords ls

---------------------------------------------------------------------------
-- MAIN                                                                  --
---------------------------------------------------------------------------
main :: IO ()
main = do
  args <- getArgs

  let (options,plainargs,_unrec,errs) = getOpt' Permute core_cli_options args
  
  unless (null errs) $ do
    putStrLn$ "Errors parsing command line options:"
    mapM_ (putStr . ("   "++)) errs       
    exitFailure

  when (ShowHelp `elem` options) $ do 
    putStrLn fullUsageInfo
    exitSuccess

  let (mode,rest) = 
        case plainargs of
         [] -> error $ "Command command expects the first argument to specify a mode, one of:\n" ++
                 unlines (map ("  "++) valid_modes) 
         (md:rst) -> (resolveMode md, rst)

  -- putStrLn ("hello world: "++show (mode,rest,options))

  ---------------------------------------------------------------------------
  -- Perform the task specified by the command line args

  catch (
    case mode of
      Download -> download options 
      Upload   -> upload options 
    ) (\e ->
        case e of
          FlagsNotValidE str -> putStrLn $ "Caught error: "++ str
      ) 



---------------------------------------------------------------------------
-- upload

upload :: [Flag] -> IO () 
upload = error "Upload functionality is not yet implemented"




---------------------------------------------------------------------------
-- download

download :: [Flag] -> IO ()
download flags = do 
  when (not flagsValid) $ throwIO $ FlagsNotValidE "The flags are invalid for a download"   


  --putStrLn $ "processing table: "++ table
  --putStrLn $ "Using ID: " ++ id
  --putStrLn $ "Using Secret: " ++ secret

  ---------------------------------------------------------------------------
  -- Initialize !
  (table_id,auth) <- init id secret table


  ---------------------------------------------------------------------------
  -- is a query specified ?
  tab <- case hasQuery of 
    True -> 
      do
        let q = parseSQLQuery query
        case q of
          Left (SQL.ParseError msg _ _ fmsg) -> error $ msg ++ "\n" ++ fmsg
          Right validQuery -> do
            -- Replace "FT" with table_id in SQL Query
            let theQuery = metaID table_id validQuery
            -- Download whatever the query specifies
            pullWithQuery table_id auth (SQL.prettyQueryExpr theQuery)
    False -> 
      error "NO QUERY: Exiting"
       -- Here the tool should go into "simple mode" for users not
       -- in love with SQL. 

  ---------------------------------------------------------------------------
  -- Do the work! 
  let csv_initial = convertToCSV flags tab
  
  ---------------------------------------------------------------------------
  -- Apply refining filters
  let csv_filtered = applyFilters flags csv_initial 

  let csv_split = applySplit flags csv_filtered 
  
  putStrLn $ printCSV $ csv_split
  where
    -- are flags valid for download ? 
    flagsValid =
      (not . null) [() | GoogleSecret _ <- flags] &&
      (not . null) [() | GoogleID _  <- flags] &&
      (not . null) [() | FTName _ <- flags] 

    -- did the user specify a query ? 
    hasQuery = (not . null) [ () | FTQuery _ <- flags]  
  
    -- assume flags valid
    secret = head [ c | GoogleSecret c <- flags]
    id     = head [ i | GoogleID i <- flags]
    table  = head [t | FTName t  <- flags]


    -- assume we have a query 
    query = head [ q | FTQuery q <- flags] 


---------------------------------------------------------------------------
-- Parse query
-- The purpose of this will (for now) simply be to check if the query is
-- wellformed. The hgdata FusionTable code currently takes the
-- query as a String (or is a ByteString).. 

parseSQLQuery :: String -> Either SQL.ParseError SQL.QueryExpr
parseSQLQuery str = SQL.parseQueryExpr "CommandLine" Nothing str 


---------------------------------------------------------------------------
-- As to not depend on the highly hacky Analytics.hs


--pullWithQuery :: String -> String -> String -> String -> IO ColData

--pullWithQuery cid sec table_name query = do
pullWithQuery table_id auth query = -- do
  -- putStrLn table_id
  getWithSQLQuery auth table_id query


---------------------------------------------------------------------------
-- metaID
-- Help the user, so he does not need to know the table_id

metaID :: String -> SQL.QueryExpr -> SQL.QueryExpr
metaID table_id qe@(SQL.Select _ _ _ _ _ _ _ _ _ ) =
  qe { SQL.qeFrom = map mangle (SQL.qeFrom qe) }
  where
    mangle (SQL.TRSimple names) = SQL.TRSimple $ map mangleNames names
    mangle sql = sql 
    
    mangleNames (SQL.Name str)   | str == "FT" = SQL.Name table_id
    mangleNames (SQL.QName str)  | str == "\"FT\"" = SQL.QName $ show table_id  
    mangleNames (SQL.UQName str) | str == "FT"  = SQL.UQName $show table_id  
    mangleNames n = n 

{-
  SQL queries look quite complicated to me.
  So here dealing with a subset of functionality.

  Need more SQL understanding, it might be possible to
  set an Alias. TRAlias. Thus change the Expr tree slightly at some
  higher location and have it permeate.
  -- NAH, the TRAlias tags probably have something to do with the
     SQL "AS" functionality. 
-} 






---------------------------------------------------------------------------
-- Pulled down table of FTValues to CSV

convertToCSV :: [Flag] -> ColData -> [[String]]
convertToCSV flags cd@(ColData cols values) =
  case (wizardMode,rawMode, flagsValid) of
    (True, False, False) -> inJuxHurYlem cols values
    (False, True, False) -> rawCSV2 cols values
    (False, False, True) -> toCSV names vars cols values
    _ -> error "Command line arguments are incorrect for CSV creation" 
    
  where 
    flagsValid =
      (not . null) [() | BenchName _ <- flags] &&
      (not . null) [() | BenchVariation _  <- flags] &&
      (not . null) [() | BenchData _ <- flags] 
    wizardMode =
      (not . null) [() | Wizard <- flags]

    rawMode =
      (not . null) [() | RawCSV <- flags] 

    -- assume flagsvalid
    name = head [n | BenchName n <- flags]
    var  = head [v | BenchVariation v <- flags]
    dat  = head [d | BenchData d <- flags]

    names = map strip $ splitOn "," name
    vars  = map strip $ splitOn "," var

-- Without any thinking, turn the table into CSV 
-- rawCSV :: [String] -> [[FTValue]] -> String
-- rawCSV cols table = header ++ "\n" ++ 
--                     rest table 
--   where
--     header = concat $ intersperse "," cols
--     rest [] = []
--     rest (x:xs) = (concat $ intersperse "," $ map ftValueToString x) ++ "\n"  ++ 
--                   rest xs

rawCSV cols table = printCSV $ rawCSV2 cols table 

rawCSV2 :: [String] -> [[FTValue]] -> [[String]]
rawCSV2 cols table = cols: map ( map ftValueToString) table 

printCSV :: [[String]] -> String
printCSV strs = unlines $ map (concat . intersperse ",")  strs

ftValueToString :: FTValue -> String
ftValueToString (DoubleValue d) = show d
ftValueToString (StringValue s) = s 


--        idBench     idVars      Colnames    the Rows 
toCSV :: [String] -> [String] -> [String] -> [[FTValue]] -> [[String]]
toCSV = error "The \"guided\" CSV generation is not implemented" 

---------------------------------------------------------------------------
-- Wizard Mode
inJuxHurYlem :: [String] -> [[FTValue]] -> [[String]]
inJuxHurYlem = error "The wizard is not available" 

-- Maybe there should be a configurable "Wizard config file" where
-- the user can specify column names and their meaning. 

---------------------------------------------------------------------------
-- GUIDELINES FOR THE WIZARD
{-
    Identifying columns in the fusiontable will generally have StringValue fields. 
    Measurement points will generally be DoubleValue.

    



-} 




---------------------------------------------------------------------------
-- FILTERING FILTERING

applyFilters :: [Flag] -> [[String]] -> [[String]]
applyFilters flags csv =
  if filtersActive
  then 
    case filterLoc of
      Row x -> applyFilterByRow x csv
      Column x -> applyFilterByColumn x csv                  
  else csv 
    
  where
    filtersActive = (not . null) [() | FilterLoc _ <- flags] &&
                    (not . null) [() | FilterBy _ <- flags]  &&
                    (not . null) [() | FilterStr _ <- flags]
    filterLoc = head [ read x :: LocationSpec | FilterLoc x <- flags]
    filterBy  = head [ read x :: FilterSpec   | FilterBy x <- flags]
    filterStr = head [ str | FilterStr str <- flags] 

    applyFilterByRow x csv = transpose $ applyFilterByColumn  x $ transpose csv
    applyFilterByColumn x csv = 
      case filterBy of
        Prefix   -> filter (\l -> filterStr `isPrefixOf` (l !! x))  csv
        Infix    -> filter (\l -> filterStr `isInfixOf` (l !! x))  csv
        Suffix  -> filter (\l -> filterStr `isSuffixOf` (l !! x))  csv



---------------------------------------------------------------------------
-- Splitting. one column into many

applySplit :: [Flag] -> [[String]] -> [[String]]
applySplit flags csv =
  if splitActive
  then
    case splitLoc of
      Row r -> error "Splitting a row is not implemented"
      Column c -> map (applySplitByColumn c) csv
  else csv
 where
    splitActive = (not . null) [() | SplitLoc _ <- flags] &&
                  (not . null) [() | SplitBy _ <- flags] 
    
    splitLoc = head [ read x :: LocationSpec | SplitLoc x <- flags]
    splitBy  = head [ x  | SplitBy x <- flags]

--     applyFilterByRow x csv = transpose $ applyFilterByColumn  x $ transpose csv
    applySplitByColumn c csv =
      let before = take c csv
          after  = drop (c+1) csv
          atx    = csv !! c
      in before ++ (splitOn splitBy atx) ++ after 

       
        
