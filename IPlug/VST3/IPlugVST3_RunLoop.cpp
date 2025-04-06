/*
 ==============================================================================

 This file is part of the iPlug 2 library. Copyright (C) the iPlug 2 developers.

 See LICENSE.txt for  more info.

 ==============================================================================
*/

#include "IPlugVST3_RunLoop.h"

BEGIN_IPLUG_NAMESPACE

struct VST3Timer : Steinberg::Linux::ITimerHandler, public Steinberg::FObject
{
  std::function<void()> callback;

  void PLUGIN_API onTimer() override
  {
    callback();
  }

  DELEGATE_REFCOUNT (Steinberg::FObject)
  DEFINE_INTERFACES
    DEF_INTERFACE (Steinberg::Linux::ITimerHandler)
  END_DEFINE_INTERFACES (Steinberg::FObject)
};

struct EventHandler : Steinberg::Linux::IEventHandler, public Steinberg::FObject
{
  IPlugVST3_RunLoop* ev;

  void PLUGIN_API onFDIsSet (Steinberg::Linux::FileDescriptor) override
  {
    // TODO update UI
  }

  DELEGATE_REFCOUNT (Steinberg::FObject)
  DEFINE_INTERFACES
    DEF_INTERFACE (Steinberg::Linux::IEventHandler)
  END_DEFINE_INTERFACES (Steinberg::FObject)
};

struct TimerHandler : Steinberg::Linux::ITimerHandler, public Steinberg::FObject
{
  IPlugVST3_RunLoop* ev;

  void PLUGIN_API onTimer () override
  {
    // TODO update UI
  }

  DELEGATE_REFCOUNT (Steinberg::FObject)
  DEFINE_INTERFACES
    DEF_INTERFACE (Steinberg::Linux::ITimerHandler)
  END_DEFINE_INTERFACES (Steinberg::FObject)
};

IPlugVST3_RunLoop* IPlugVST3_RunLoop::Create(Steinberg::FUnknown *frame)
{
  auto ev = new IPlugVST3_RunLoop();

  Steinberg::FUnknownPtr<Steinberg::Linux::IRunLoop> runLoop(frame);
  ev->runLoop = runLoop;
  if(!ev->runLoop)
  {
    delete ev;
    return nullptr;
  }

  return ev;
}

void IPlugVST3_RunLoop::Destory(IPlugVST3_RunLoop* self)
{
}

VST3Timer* IPlugVST3_RunLoop::CreateTimer(std::function<void()> callback, int msec)
{
  auto tm = new VST3Timer();
  tm->callback = callback;
  if (runLoop->registerTimer(tm, msec) == Steinberg::kResultOk)
  {
    mTimers.Add(tm);
    return tm;
  }
  else
  {
    delete tm;
    return nullptr;
  }
}

void IPlugVST3_RunLoop::DestroyTimer(VST3Timer* timer)
{
  runLoop->unregisterTimer(timer);
  mTimers.Delete(mTimers.FindR(timer));
  delete timer;
}

END_IPLUG_NAMESPACE
