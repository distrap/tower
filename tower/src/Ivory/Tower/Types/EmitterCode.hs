{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ExistentialQuantification #-}

module Ivory.Tower.Types.EmitterCode
  ( EmitterCode(..)
  , EmitState(..)
  , SomeEmitterCode(..)
  , prettyEmitSuffix
  , someemittercode_deliver
  , someemittercode_init
  , someemittercode_gen
  , someemittercode_user
  ) where

import Ivory.Language

data SomeEmitterCode = forall a . SomeEmitterCode (EmitterCode a)

someemittercode_deliver :: SomeEmitterCode -> Ivory eff ()
someemittercode_deliver (SomeEmitterCode c) = emittercode_deliver c
someemittercode_init :: SomeEmitterCode -> Ivory eff ()
someemittercode_init (SomeEmitterCode c) = emittercode_init c
someemittercode_gen :: SomeEmitterCode -> ModuleDef
someemittercode_gen (SomeEmitterCode c) = emittercode_gen c
someemittercode_user :: SomeEmitterCode -> ModuleDef
someemittercode_user (SomeEmitterCode c) = emittercode_user c

data EmitterCode (a :: Area *) = EmitterCode
  { emittercode_init :: forall eff. Ivory eff ()
  , emittercode_deliver :: forall eff. Ivory eff ()
  , emittercode_user :: ModuleDef
  , emittercode_gen :: ModuleDef
  }

-- | Emitter actions.
data EmitState =
    Init
  | Emit
  | Deliver
  | Msg Integer
  | MsgCnt
  deriving (Show, Read, Eq)

-- | Create consistent suffixes from actions.
prettyEmitSuffix :: EmitState -> String
prettyEmitSuffix e =
  case e of
    Init    -> "init"
    Emit    -> "emit"
    Deliver -> "deliver"
    Msg bnd -> "message_" ++ show bnd
    MsgCnt  -> "message_count"
