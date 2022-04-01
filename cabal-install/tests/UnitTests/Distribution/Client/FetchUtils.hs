{-# LANGUAGE ScopedTypeVariables #-}
module UnitTests.Distribution.Client.FetchUtils
  ( tests,
  )
where

import Control.Concurrent (threadDelay)
import Control.Exception
import Data.Time.Clock (NominalDiffTime, UTCTime, diffUTCTime, getCurrentTime)
import Distribution.Client.FetchUtils
import Distribution.Client.GlobalFlags (RepoContext (..))
import Distribution.Client.HttpUtils (HttpCode, HttpTransport (..))
import Distribution.Client.Types.PackageLocation (PackageLocation (..), ResolvedPkgLoc)
import Distribution.Client.Types.Repo (Repo (..), emptyRemoteRepo)
import Distribution.Client.Types.RepoName (RepoName (..))
import Distribution.Types.PackageId (PackageIdentifier (..), RepoUpdate(..), getRepoUpdate, PackageId)
import Distribution.Types.PackageName (mkPackageName, unPackageName)
import qualified Distribution.Verbosity as Verbosity
import Distribution.Version (mkVersion)
import Network.URI (URI, uriPath)
import Test.Tasty
import Test.Tasty.HUnit
import UnitTests.TempTestDir (withTestDir)

tests :: [TestTree]
tests =
  [ testGroup
      "asyncFetchPackages"
      [ testCase "handles an empty package list" testEmpty,
        testCase "passes an unpacked local package through" testPassLocalPackage,
        testCase "handles http" testHttp,
        testCase "aborts on interrupt in GET" $ testGetInterrupt,
        testCase "aborts on other exception in GET" $ testGetException,
        testCase "aborts on interrupt in GET (uncollected download)" $ testUncollectedInterrupt,
        testCase "continues on other exception in GET (uncollected download)" $ testUncollectedException,
        testCase "parses repo package updates" $ testUpdateVerbosity oldDependencies newDependencies
      ]
  ]

verbosity :: Verbosity.Verbosity
verbosity = Verbosity.silent

-- | An interval that we use to assert that something happens "immediately".
-- Must be shorter than 'longSleep' to ensure those are interrupted.
-- 1s would be a reasonable value, but failed tempfile cleanup on Windows CI
-- takes ~1s.
shortDelta :: NominalDiffTime
shortDelta = 5 -- 5s

longSleep :: IO ()
longSleep = threadDelay 10000000 -- 10s

testEmpty :: Assertion
testEmpty = do
  let repoCtxt = undefined
      pkgLocs = []
  res <- asyncFetchPackages verbosity repoCtxt pkgLocs $ \_ ->
    return ()
  res @?= ()

testPassLocalPackage :: Assertion
testPassLocalPackage = do
  let repoCtxt = error "repoCtxt undefined"
      loc = LocalUnpackedPackage "a"
  res <- asyncFetchPackages verbosity repoCtxt [loc] $ \downloadMap ->
    waitAsyncFetchPackage verbosity downloadMap loc
  res @?= LocalUnpackedPackage "a"

testHttp :: Assertion
testHttp = withFakeRepoCtxt get200 $ \repoCtxt repo -> do
  let pkgId = mkPkgId "foo"
      loc = RepoTarballPackage repo pkgId Nothing
  res <- asyncFetchPackages verbosity repoCtxt [loc] $ \downloadMap ->
    waitAsyncFetchPackage verbosity downloadMap loc
  case res of
    RepoTarballPackage repo' pkgId' _ -> do
      repo' @?= repo
      pkgId' @?= pkgId
    _ -> assertFailure $ "expected RepoTarballPackage, got " ++ show res
  where
    get200 = \_uri -> return 200

testGetInterrupt :: Assertion
testGetInterrupt = testGetAny UserInterrupt

testGetException :: Assertion
testGetException = testGetAny $ userError "some error"

-- | Test that if a GET request fails with the given exception,
-- we exit promptly. We queue two slow downloads after the failing
-- download to cover a buggy scenario where
-- 1. first download throws
-- 2. second download is cancelled, but swallows AsyncCancelled
-- 3. third download keeps running
testGetAny :: Exception e => e -> Assertion
testGetAny exc = withFakeRepoCtxt get $ \repoCtxt repo -> do
  let loc pkgId = RepoTarballPackage repo pkgId Nothing
      pkgLocs = [loc throws, loc slowA, loc slowB]

  start <- getCurrentTime
  res :: Either SomeException ResolvedPkgLoc <-
    try $
      asyncFetchPackages verbosity repoCtxt pkgLocs $ \downloadMap -> do
        waitAsyncFetchPackage verbosity downloadMap (loc throws)
  assertFaster start shortDelta
  case res of
    Left _ -> pure ()
    Right _ -> assertFailure $ "expected an exception, got " ++ show res
  where
    throws = mkPkgId "throws"
    slowA = mkPkgId "slowA"
    slowB = mkPkgId "slowB"
    get uri = case uriPath uri of
      "package/throws-1.0.tar.gz" -> throwIO exc
      "package/slowA-1.0.tar.gz" -> longSleep >> return 200
      "package/slowB-1.0.tar.gz" -> longSleep >> return 200
      _ -> assertFailure $ "unexpected URI: " ++ show uri

-- | Test that when an undemanded download is interrupted (Ctrl-C),
-- we still abort directly.
testUncollectedInterrupt :: Assertion
testUncollectedInterrupt = withFakeRepoCtxt get $ \repoCtxt repo -> do
  let loc pkgId = RepoTarballPackage repo pkgId Nothing
      pkgLocs = [loc throws, loc slowA, loc slowB]

  start <- getCurrentTime
  res :: Either SomeException ResolvedPkgLoc <-
    try $
      asyncFetchPackages verbosity repoCtxt pkgLocs $ \downloadMap -> do
        waitAsyncFetchPackage verbosity downloadMap (loc slowA)
  assertFaster start shortDelta
  case res of
    Left _ -> pure ()
    Right _ -> assertFailure $ "expected an exception, got " ++ show res
  where
    throws = mkPkgId "throws"
    slowA = mkPkgId "slowA"
    slowB = mkPkgId "slowB"
    get uri = case uriPath uri of
      "package/throws-1.0.tar.gz" -> throwIO UserInterrupt
      "package/slowA-1.0.tar.gz" -> longSleep >> return 200
      "package/slowB-1.0.tar.gz" -> longSleep >> return 200
      _ -> assertFailure $ "unexpected URI: " ++ show uri

-- | Test that a download failure doesn't automatically abort things,
-- e.g. if we don't collect the download. (In practice, we might collect
-- the download and handle its exception.)
testUncollectedException :: Assertion
testUncollectedException = withFakeRepoCtxt get $ \repoCtxt repo -> do
  let loc pkgId = RepoTarballPackage repo pkgId Nothing
      pkgLocs = [loc throws, loc foo]

  start <- getCurrentTime
  res <- asyncFetchPackages verbosity repoCtxt pkgLocs $ \downloadMap -> do
    waitAsyncFetchPackage verbosity downloadMap (loc foo)
  assertFaster start shortDelta
  case res of
    RepoTarballPackage repo' pkgId' _ -> do
      repo' @?= repo
      pkgId' @?= foo
    _ -> assertFailure $ "expected RepoTarballPackage, got " ++ show res
  where
    throws = mkPkgId "throws"
    foo = mkPkgId "foo"
    get uri = case uriPath uri of
      "package/throws-1.0.tar.gz" -> throwIO $ userError "failed download"
      "package/foo-1.0.tar.gz" -> return 200
      _ -> assertFailure $ "unexpected URI: " ++ show uri

assertFaster :: UTCTime -> NominalDiffTime -> Assertion
assertFaster start delta = do
  t <- getCurrentTime
  assertBool ("took longer than " ++ show delta) (diffUTCTime t start < delta)

mkPkgId :: String -> PackageIdentifier
mkPkgId name = PackageIdentifier (mkPackageName name) (mkVersion [1, 0])

-- | Provide a repo and a repo context with the given GET handler.
withFakeRepoCtxt ::
  (URI -> IO HttpCode) ->
  (RepoContext -> Repo -> IO a) ->
  IO a
withFakeRepoCtxt handleGet action =
  withTestDir verbosity "fake repo" $ \tmpDir ->
    let repo =
          RepoRemote
            { repoRemote = emptyRemoteRepo $ RepoName "fake",
              repoLocalDir = tmpDir
            }
        repoCtxt =
          RepoContext
            { repoContextRepos = [repo],
              repoContextGetTransport = return httpTransport,
              repoContextWithSecureRepo = \_ _ ->
                error "fake repo ctxt: repoContextWithSecureRepo not implemented",
              repoContextIgnoreExpiry = error "fake repo ctxt: repoContextIgnoreExpiry not implemented"
            }
     in action repoCtxt repo
  where
    httpTransport =
      HttpTransport
        { getHttp = \_verbosity uri _etag _filepath _headers -> do
            code <- handleGet uri
            return (code, Nothing),
          postHttp = error "fake transport: postHttp not implemented",
          postHttpFile = error "fake transport: postHttpFile not implemented",
          putHttpFile = error "fake transport: putHttp not implemented",
          transportSupportsHttps = error "fake transport: transportSupportsHttps not implemented",
          transportManuallySelected = True
        }

testUpdateVerbosity :: [PackageId] -> [PackageId] -> Assertion 
testUpdateVerbosity oldDeps newDeps = do  
  let repoUpdate = getRepoUpdate oldDeps newDeps
  1 @=? numPackagesAdded repoUpdate
  1 @=? (length . packagesAdded $ repoUpdate)
  mkVersion [1,0,0] @=? (pkgVersion . head . packagesAdded $ repoUpdate)
  "Four" @=? (getPackageName . head . packagesAdded $ repoUpdate)
  1 @=? numPackagesUpdated repoUpdate
  1 @=? (length . packagesUpdated $ repoUpdate)
  "Two" @=? (getPackageName . head . packagesUpdated $ repoUpdate)
  mkVersion [1,2,0] @=? (pkgVersion . head . packagesUpdated $ repoUpdate)
  1 @=? numPackagesRemoved repoUpdate
  1 @=? (length . packagesRemoved $ repoUpdate)
  "Three" @=? (getPackageName . head . packagesRemoved $ repoUpdate)
  where
    getPackageName :: PackageId -> String
    getPackageName (PackageIdentifier name _) = unPackageName name

mkPkgVer :: String -> [Int] -> PackageId
mkPkgVer name ver = PackageIdentifier (mkPackageName name) (mkVersion ver)

oldDependencies :: [PackageId]
oldDependencies = [
    mkPkgVer "One" [1,0,0],
    mkPkgVer "Two" [1,0,0],
    mkPkgVer "Three" [1,0,0]
  ]

newDependencies :: [PackageId]
newDependencies = [
  mkPkgVer "One" [1,0,0],
  mkPkgVer "Two" [1,1,0],
  mkPkgVer "Two" [1,2,0],
  mkPkgVer "Four" [0,9,0],
  mkPkgVer "Four" [1,0,0]
  ]