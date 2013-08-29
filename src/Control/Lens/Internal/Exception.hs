{-# LANGUAGE CPP #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE FlexibleInstances #-}
#if __GLASGOW_HASKELL__ && __GLASGOW_HASKELL__ >= 707
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE PolyKinds #-}
#endif
{-# LANGUAGE KindSignatures #-}
#ifdef TRUSTWORTHY
{-# LANGUAGE Trustworthy #-}
#endif
-----------------------------------------------------------------------------
-- |
-- Module      :  Control.Lens.Internal.Exception
-- Copyright   :  (C) 2013 Edward Kmett
-- License     :  BSD-style (see the file LICENSE)
-- Maintainer  :  Edward Kmett <ekmett@gmail.com>
-- Stability   :  experimental
-- Portability :  non-portable
--
-- This module uses dirty tricks to generate a 'Handler' from an arbitrary
-- 'Fold'.
----------------------------------------------------------------------------
module Control.Lens.Internal.Exception
  ( Handleable(..)
  , HandlingException(..)
  ) where

import Control.Exception as Exception
import Control.Lens.Fold
import Control.Lens.Getter
import Control.Lens.Internal.Reflection
import Control.Monad.Catch as Catch
import Data.Monoid
import Data.Proxy
import Data.Typeable

#if defined(__GLASGOW_HASKELL__) && __GLASGOW_HASKELL__ >= 707
type Typeable1 = Typeable
#endif

------------------------------------------------------------------------------
-- Handlers
------------------------------------------------------------------------------

-- | Both @MonadCatchIO-transformers@ and "Control.Exception" provide a 'Handler' type.
--
-- This lets us write combinators to build handlers that are agnostic about the choice of
-- which of these they use.
class Handleable e (m :: * -> *) (h :: * -> *) | h -> e m where
  -- | This builds a 'Handler' for just the targets of a given 'Control.Lens.Type.Prism' (or any 'Getter', really).
  --
  -- @
  -- 'catches' ... [ 'handler' 'Control.Exception.Lens._AssertionFailed' (\s -> 'print' '$' \"Assertion Failed\\n\" '++' s)
  --             , 'handler' 'Control.Exception.Lens._ErrorCall' (\s -> 'print' '$' \"Error\\n\" '++' s)
  --             ]
  -- @
  --
  -- This works ith both the 'Exception.Handler' type provided by @Control.Exception@:
  --
  -- @
  -- 'handler' :: 'Getter'     'SomeException' a -> (a -> 'IO' r) -> 'Exception.Handler' r
  -- 'handler' :: 'Fold'       'SomeException' a -> (a -> 'IO' r) -> 'Exception.Handler' r
  -- 'handler' :: 'Control.Lens.Prism.Prism''     'SomeException' a -> (a -> 'IO' r) -> 'Exception.Handler' r
  -- 'handler' :: 'Control.Lens.Lens.Lens''      'SomeException' a -> (a -> 'IO' r) -> 'Exception.Handler' r
  -- 'handler' :: 'Control.Lens.Traversal.Traversal'' 'SomeException' a -> (a -> 'IO' r) -> 'Exception.Handler' r
  -- @
  --
  -- and with the 'CatchIO.Handler' type provided by @Control.Monad.CatchIO@:
  --
  -- @
  -- 'handler' :: 'Getter'     'SomeException' a -> (a -> m r) -> 'CatchIO.Handler' m r
  -- 'handler' :: 'Fold'       'SomeException' a -> (a -> m r) -> 'CatchIO.Handler' m r
  -- 'handler' :: 'Control.Lens.Prism.Prism''     'SomeException' a -> (a -> m r) -> 'CatchIO.Handler' m r
  -- 'handler' :: 'Control.Lens.Lens.Lens''      'SomeException' a -> (a -> m r) -> 'CatchIO.Handler' m r
  -- 'handler' :: 'Control.Lens.Traversal.Traversal'' 'SomeException' a -> (a -> m r) -> 'CatchIO.Handler' m r
  -- @
  --
  -- and with the 'Control.Monad.Error.Lens.Handler' type provided by @Control.Monad.Error.Lens@:
  --
  -- @
  -- 'handler' :: 'Getter'     e a -> (a -> m r) -> 'Control.Monad.Error.Lens.Handler' e m r
  -- 'handler' :: 'Fold'       e a -> (a -> m r) -> 'Control.Monad.Error.Lens.Handler' e m r
  -- 'handler' :: 'Control.Lens.Prism.Prism''     e a -> (a -> m r) -> 'Control.Monad.Error.Lens.Handler' e m r
  -- 'handler' :: 'Control.Lens.Lens.Lens''      e a -> (a -> m r) -> 'Control.Monad.Error.Lens.Handler' e m r
  -- 'handler' :: 'Control.Lens.Traversal.Traversal'' e a -> (a -> m r) -> 'Control.Monad.Error.Lens.Handler' e m r
  -- @
  handler :: Typeable a => Getting (First a) e a -> (a -> m r) -> h r

  -- | This builds a 'Handler' for just the targets of a given 'Control.Lens.Prism.Prism' (or any 'Getter', really).
  -- that ignores its input and just recovers with the stated monadic action.
  --
  -- @
  -- 'catches' ... [ 'handler_' 'Control.Exception.Lens._NonTermination' ('return' \"looped\")
  --             , 'handler_' 'Control.Exception.Lens._StackOverflow' ('return' \"overflow\")
  --             ]
  -- @
  --
  -- This works with the 'Exception.Handler' type provided by @Control.Exception@:
  --
  -- @
  -- 'handler_' :: 'Getter'     'SomeException' a -> 'IO' r -> 'Exception.Handler' r
  -- 'handler_' :: 'Fold'       'SomeException' a -> 'IO' r -> 'Exception.Handler' r
  -- 'handler_' :: 'Control.Lens.Prism.Prism''     'SomeException' a -> 'IO' r -> 'Exception.Handler' r
  -- 'handler_' :: 'Control.Lens.Lens.Lens''      'SomeException' a -> 'IO' r -> 'Exception.Handler' r
  -- 'handler_' :: 'Control.Lens.Traversal.Traversal'' 'SomeException' a -> 'IO' r -> 'Exception.Handler' r
  -- @
  --
  -- and with the 'CatchIO.Handler' type provided by @Control.Monad.CatchIO@:
  --
  -- @
  -- 'handler_' :: 'Getter'     'SomeException' a -> m r -> 'CatchIO.Handler' m r
  -- 'handler_' :: 'Fold'       'SomeException' a -> m r -> 'CatchIO.Handler' m r
  -- 'handler_' :: 'Control.Lens.Prism.Prism''     'SomeException' a -> m r -> 'CatchIO.Handler' m r
  -- 'handler_' :: 'Control.Lens.Lens.Lens''      'SomeException' a -> m r -> 'CatchIO.Handler' m r
  -- 'handler_' :: 'Control.Lens.Traversal.Traversal'' 'SomeException' a -> m r -> 'CatchIO.Handler' m r
  -- @
  --
  -- and with the 'Control.Monad.Error.Lens.Handler' type provided by @Control.Monad.Error.Lens@:
  --
  -- @
  -- 'handler_' :: 'Getter'     e a -> m r -> 'Control.Monad.Error.Lens.Handler' e m r
  -- 'handler_' :: 'Fold'       e a -> m r -> 'Control.Monad.Error.Lens.Handler' e m r
  -- 'handler_' :: 'Control.Lens.Prism.Prism''     e a -> m r -> 'Control.Monad.Error.Lens.Handler' e m r
  -- 'handler_' :: 'Control.Lens.Lens.Lens''      e a -> m r -> 'Control.Monad.Error.Lens.Handler' e m r
  -- 'handler_' :: 'Control.Lens.Traversal.Traversal'' e a -> m r -> 'Control.Monad.Error.Lens.Handler' e m r
  -- @
  handler_ :: Typeable a => Getting (First a) e a -> m r -> h r
  handler_ l = handler l . const
  {-# INLINE handler_ #-}

instance Handleable SomeException IO Exception.Handler where
  handler = handlerIO

instance Typeable1 m => Handleable SomeException m (Catch.Handler m) where
  handler = handlerCatchIO

handlerIO :: forall a r. Typeable a => Getting (First a) SomeException a -> (a -> IO r) -> Exception.Handler r
handlerIO l f = reifyTypeable (preview l) $ \ (_ :: Proxy s) -> Exception.Handler (\(Handling a :: Handling a s IO) -> f a)

handlerCatchIO :: forall m a r. (Typeable a, Typeable1 m) => Getting (First a) SomeException a -> (a -> m r) -> Catch.Handler m r
handlerCatchIO l f = reifyTypeable (preview l) $ \ (_ :: Proxy s) -> Catch.Handler (\(Handling a :: Handling a s m) -> f a)

------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------

-- | There was an 'Exception' caused by abusing the internals of a 'Handler'.
data HandlingException = HandlingException deriving (Show,Typeable)

instance Exception HandlingException

{-
-- | This supplies a globally unique set of IDs so we can hack around the default use of 'cast' in 'SomeException'
-- if someone, somehow, somewhere decides to reach in and catch and rethrow a @Handling@ 'Exception' by existentially
-- opening a 'Handler' that uses it.
supply :: IORef Int
supply = unsafePerformIO $ newIORef 0
{-# NOINLINE supply #-}
-}

-- | This permits the construction of an \"impossible\" 'Control.Exception.Handler' that matches only if some function does.
newtype Handling a s (m :: * -> *) = Handling a
#if defined(__GLASGOW_HASKELL__) && __GLASGOW_HASKELL__ >= 707
  deriving Typeable
#else
-- the m parameter exists simply to break the Typeable1 pattern, so we can provide this without overlap.
-- here we simply generate a fresh TypeRep so we'll fail to compare as equal to any other TypeRep.
instance (Typeable a, Typeable s, Typeable1 m) => Typeable (Handling a s m) where
  typeOf _ = mkTyConApp handlingTyCon [typeOf (undefined :: a), typeOf (undefined :: s), typeOf1 (undefined :: m a)]
  {-# INLINE typeOf #-}

handlingTyCon :: TyCon
#if MIN_VERSION_base(4,4,0)
handlingTyCon = mkTyCon3 "lens" "Control.Lens.Internal.Exception" "Handling"
#else
handlingTyCon = mkTyCon "Control.Lns.Internal.Exception.Handling"
#endif
{-# NOINLINE handlingTyCon #-}
#endif

-- The @Handling@ wrapper is uninteresting, and should never be thrown, so you won't get much benefit here.
instance Show (Handling a s m) where
  showsPrec d _ = showParen (d > 10) $ showString "Handling ..."
  {-# INLINE showsPrec #-}

instance (Reifies s (SomeException -> Maybe a), Typeable a, Typeable1 m, Typeable s) => Exception (Handling a s m) where
  toException _ = SomeException HandlingException
  {-# INLINE toException #-}
  fromException = fmap Handling . reflect (Proxy :: Proxy s)
  {-# INLINE fromException #-}
