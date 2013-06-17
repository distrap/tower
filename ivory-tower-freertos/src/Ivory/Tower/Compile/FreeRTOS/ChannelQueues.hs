{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE TypeOperators #-}


module Ivory.Tower.Compile.FreeRTOS.ChannelQueues where

import Text.Printf

import Ivory.Language
import Ivory.Stdlib
import qualified Ivory.OS.FreeRTOS.Queue as Q
import           Ivory.OS.FreeRTOS.Queue (QueueHandle)

import Ivory.Tower.Types
import Ivory.Tower.Compile.FreeRTOS.Types

type EventQueueLen = 16
type EventQueueIx  = Ix EventQueueLen

data FreeRTOSChannel area =
  FreeRTOSChannel
    { fch_name :: String
    , fch_emit :: forall eff s cs . (eff `AllocsIn` cs)
               => Ctx -> ConstRef s area -> Ivory eff IBool
    , fch_receive :: forall eff s cs . (eff `AllocsIn` cs)
                  => Ctx -> Ref s area -> Ivory eff IBool
    , fch_initDef :: Def('[]:->())
    , fch_moduleDef :: ModuleDef
    , fch_channelid :: ChannelId
    }

data FreeRTOSGuard =
  FreeRTOSGuard
    { guard_block     :: forall eff cs . (eff `AllocsIn` cs) => Uint32 -> Ivory eff IBool
    , guard_notify    :: forall eff . Ctx -> Ivory eff ()
    , guard_initDef   :: Def('[]:->())
    , guard_moduleDef :: ModuleDef
    }

eventGuard :: TaskNode -> FreeRTOSGuard
eventGuard node = FreeRTOSGuard
  { guard_block = block
  , guard_notify = notify
  , guard_initDef = initDef
  , guard_moduleDef = moduleDef
  }
  where
  unique s = s ++ (nodest_name node)

  block :: (eff `AllocsIn` cs) => Uint32 -> Ivory eff IBool
  block time = do
    vlocal <- local (ival 0) -- Don't care about value rxed
    guardQueue <- addrOf guardQueueArea
    got <- call Q.receive guardQueue vlocal time
    return got

  notify :: Ctx -> Ivory eff ()
  notify ctx = do
    guardQueue <- addrOf guardQueueArea
    let sentvalue = 0 -- we don't care what the value in the queue is, just its presence
        blocktime = 0 -- we don't ever want to block, and if the queue is full thats OK
    case ctx of
      User -> call_ Q.send     guardQueue sentvalue blocktime
      ISR  -> call_ Q.send_isr guardQueue sentvalue

  guardQueueArea :: MemArea Q.Queue
  guardQueueArea = area (unique "guardQueue") Nothing

  initDef = proc (unique "freertos_guard_init_") $ body $ do
    guardQueue <- addrOf guardQueueArea
    call_ Q.create guardQueue 1 -- create queue with single element
    retVoid

  moduleDef = do
    incl initDef
    private $ defMemArea guardQueueArea

eventQueue :: forall (area :: Area) i. (IvoryArea area)
           => ChannelId
           -> NodeSt i -- Destination Node
           -> FreeRTOSChannel area
eventQueue channelid dest = FreeRTOSChannel
  { fch_name        = unique "freertos_eventQueue"
  , fch_emit        = emit
  , fch_receive     = receive
  , fch_initDef     = initDef
  , fch_moduleDef   = mdef
  , fch_channelid   = channelid
  }
  where
  name = printf "channel%d_%s" (unChannelId channelid) (nodest_name dest)
  unique :: String -> String
  unique n = n ++ name
  eventHeapArea :: MemArea (Array EventQueueLen area)
  eventHeapArea = area (unique "eventHeap") Nothing
  pendingQueueArea, freeQueueArea :: MemArea Q.Queue
  pendingQueueArea = area (unique "pendingQueue") Nothing
  freeQueueArea    = area (unique "freeQueue") Nothing

  getIx :: (eff `AllocsIn` cs)
        => Ctx -> QueueHandle -> Uint32 -> Ivory eff (IBool, EventQueueIx)
  getIx ctx q waittime = do
    vlocal <- local (ival 0)
    s <- case ctx of
           User -> call Q.receive     q vlocal waittime
           ISR  -> call Q.receive_isr q vlocal
    v <- deref vlocal
    i <- assign (toIx v)
    return (s, i)

  putIx :: Ctx -> QueueHandle -> EventQueueIx -> Ivory eff ()
  putIx ctx q i = case ctx of
    User -> call_ Q.send     q (safeCast i) 0 -- should never block
    ISR  -> call_ Q.send_isr q (safeCast i)

  emit :: (eff `AllocsIn` cs) => Ctx -> ConstRef s area -> Ivory eff IBool
  emit ctx v = do
    eventHeap    <- addrOf eventHeapArea
    pendingQueue <- addrOf pendingQueueArea
    freeQueue    <- addrOf freeQueueArea
    (got, i) <- getIx ctx freeQueue 0
    when got $ do
      refCopy (eventHeap ! i) v
      putIx ctx pendingQueue i
    return got

  receive :: (eff `AllocsIn` cs) => Ctx -> Ref s area -> Ivory eff IBool
  receive ctx v = do
    eventHeap    <- addrOf eventHeapArea
    pendingQueue <- addrOf pendingQueueArea
    freeQueue    <- addrOf freeQueueArea
    (got, i) <- getIx ctx pendingQueue 0
    when got $ do
      refCopy v (constRef (eventHeap ! i))
      putIx ctx freeQueue i
    return got

  initName = unique "freertos_eventQueue_init"
  initDef :: Def ('[] :-> ())
  initDef = proc initName $ body $ do
    eventHeap    <- addrOf eventHeapArea
    pendingQueue <- addrOf pendingQueueArea
    freeQueue    <- addrOf freeQueueArea
    call_ Q.create pendingQueue (arrayLen eventHeap)
    call_ Q.create freeQueue    (arrayLen eventHeap)
    for (toIx (arrayLen eventHeap :: Sint32) :: EventQueueIx) $ \i ->
      call_ Q.send freeQueue (safeCast i) 0 -- should not bock

  mdef = do
    incl initDef
    private $ do
      defMemArea eventHeapArea
      defMemArea pendingQueueArea
      defMemArea freeQueueArea

