{-# LANGUAGE DeriveGeneric #-}
module Distribution.Simple.Build.Macros.Z (render, Z(..), ZPackage (..), ZTool (..)) where
import Distribution.ZinzaPrelude
data Z
    = Z {zPackages :: ([ZPackage]),
         zTools :: ([ZTool]),
         zPackageKey :: String,
         zComponentId :: String,
         zPackageVersion :: Version,
         zNotNull :: (String -> Bool),
         zManglePkgName :: (PackageName -> String),
         zMangleStr :: (String -> String)}
    deriving Generic
data ZPackage
    = ZPackage {zpkgName :: PackageName,
                zpkgVersion :: Version,
                zpkgX :: String,
                zpkgY :: String,
                zpkgZ :: String}
    deriving Generic
data ZTool
    = ZTool {ztoolName :: String,
             ztoolVersion :: Version,
             ztoolX :: String,
             ztoolY :: String,
             ztoolZ :: String}
    deriving Generic
render :: Z -> String
render z_root = execWriter $ do
  tell "/* DO NOT EDIT: This file is automatically generated by Cabal */\n"
  tell "\n"
  forM_ (zPackages z_root) $ \z_var0_pkg -> do
    tell "/* package "
    tell (prettyShow (zpkgName z_var0_pkg))
    tell "-"
    tell (prettyShow (zpkgVersion z_var0_pkg))
    tell " */\n"
    tell "#ifndef VERSION_"
    tell (zManglePkgName z_root (zpkgName z_var0_pkg))
    tell "\n"
    tell "#define VERSION_"
    tell (zManglePkgName z_root (zpkgName z_var0_pkg))
    tell " \""
    tell (prettyShow (zpkgVersion z_var0_pkg))
    tell "\"\n"
    tell "#endif /* VERSION_"
    tell (zManglePkgName z_root (zpkgName z_var0_pkg))
    tell " */\n"
    tell "#ifndef MIN_VERSION_"
    tell (zManglePkgName z_root (zpkgName z_var0_pkg))
    tell "\n"
    tell "#define MIN_VERSION_"
    tell (zManglePkgName z_root (zpkgName z_var0_pkg))
    tell "(major1,major2,minor) (\\\n"
    tell "  (major1) <  "
    tell (zpkgX z_var0_pkg)
    tell " || \\\n"
    tell "  (major1) == "
    tell (zpkgX z_var0_pkg)
    tell " && (major2) <  "
    tell (zpkgY z_var0_pkg)
    tell " || \\\n"
    tell "  (major1) == "
    tell (zpkgX z_var0_pkg)
    tell " && (major2) == "
    tell (zpkgY z_var0_pkg)
    tell " && (minor) <= "
    tell (zpkgZ z_var0_pkg)
    tell ")\n"
    tell "#endif /* MIN_VERSION_"
    tell (zManglePkgName z_root (zpkgName z_var0_pkg))
    tell " */\n"
  tell "\n"
  forM_ (zTools z_root) $ \z_var1_tool -> do
    tell "/* package "
    tell (ztoolName z_var1_tool)
    tell "-"
    tell (prettyShow (ztoolVersion z_var1_tool))
    tell " */\n"
    tell "#ifndef TOOL_VERSION_"
    tell (zMangleStr z_root (ztoolName z_var1_tool))
    tell "\n"
    tell "#define TOOL_VERSION_"
    tell (zMangleStr z_root (ztoolName z_var1_tool))
    tell " \""
    tell (prettyShow (ztoolVersion z_var1_tool))
    tell "\"\n"
    tell "#endif /* VERSION_"
    tell (zMangleStr z_root (ztoolName z_var1_tool))
    tell " */\n"
    tell "#ifndef MIN_TOOL_VERSION_"
    tell (zMangleStr z_root (ztoolName z_var1_tool))
    tell "\n"
    tell "#define MIN_TOOL_VERSION_"
    tell (zMangleStr z_root (ztoolName z_var1_tool))
    tell "(major1,major2,minor) (\\\n"
    tell "  (major1) <  "
    tell (ztoolX z_var1_tool)
    tell " || \\\n"
    tell "  (major1) == "
    tell (ztoolX z_var1_tool)
    tell " && (major2) <  "
    tell (ztoolY z_var1_tool)
    tell " || \\\n"
    tell "  (major1) == "
    tell (ztoolX z_var1_tool)
    tell " && (major2) == "
    tell (ztoolY z_var1_tool)
    tell " && (minor) <= "
    tell (ztoolZ z_var1_tool)
    tell ")\n"
    tell "#endif /* MIN_VERSION_"
    tell (zMangleStr z_root (ztoolName z_var1_tool))
    tell " */\n"
  tell "\n"
  if (zNotNull z_root (zPackageKey z_root))
  then do
    tell "#ifndef CURRENT_packageKey\n"
    tell "#define CURRENT_packageKey \""
    tell (zPackageKey z_root)
    tell "\"\n"
    tell "#endif /* CURRENT_packageKey */\n"
    return ()
  else do
    return ()
  if (zNotNull z_root (zComponentId z_root))
  then do
    tell "#ifndef CURRENT_COMPONENT_ID\n"
    tell "#define CURRENT_COMPONENT_ID \""
    tell (zComponentId z_root)
    tell "\"\n"
    tell "#endif /* CURRENT_COMPONENT_ID */\n"
    return ()
  else do
    return ()
  tell "#ifndef CURRENT_PACKAGE_VERSION\n"
  tell "#define CURRENT_PACKAGE_VERSION \""
  tell (prettyShow (zPackageVersion z_root))
  tell "\"\n"
  tell "#endif /* CURRENT_PACKAGE_VERSION */\n"
