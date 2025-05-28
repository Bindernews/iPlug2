/*
 ==============================================================================

 This file is part of the iPlug 2 library. Copyright (C) the iPlug 2 developers.

 See LICENSE.txt for  more info.

 ==============================================================================
*/

/**
 * @file
 * @brief Timer implementation
 */

#include "IPlugTimer.h"
#include "IPlugTaskThread.h"
#include <stdint.h>
#include <cstring>
#include <cmath>
#include "ptrlist.h"
#include "mutex.h"

#if defined OS_LINUX && defined APP_API
#include "swell.h"
#elif defined OS_LINUX
#include <signal.h>
#include <time.h>
#endif

#if defined OS_MAC || defined OS_IOS
#include <CoreFoundation/CoreFoundation.h>
#elif defined OS_WEB
#include <emscripten/html5.h>
#endif

using namespace iplug;

#if defined OS_MAC || defined OS_IOS

class Timer_impl : public Timer
{
public:
  Timer_impl(ITimerFunction func, uint32_t intervalMs);
  ~Timer_impl();

  void Stop() override;
  static void TimerProc(CFRunLoopTimerRef timer, void *info);

private:
  CFRunLoopTimerRef mOSTimer;
  ITimerFunction mTimerFunc;
  uint32_t mIntervalMs;
};

Timer* Timer::Create(ITimerFunction func, uint32_t intervalMs)
{
  return new Timer_impl(func, intervalMs);
}

Timer_impl::Timer_impl(ITimerFunction func, uint32_t intervalMs)
: mTimerFunc(func)
, mIntervalMs(intervalMs)
{
  CFRunLoopTimerContext context;
  context.version = 0;
  context.info = this;
  context.retain = nullptr;
  context.release = nullptr;
  context.copyDescription = nullptr;
  CFTimeInterval interval = intervalMs / 1000.0;
  CFRunLoopRef runLoop = CFRunLoopGetMain();
  mOSTimer = CFRunLoopTimerCreate(kCFAllocatorDefault, CFAbsoluteTimeGetCurrent(), interval, 0, 0, TimerProc, &context);
  CFRunLoopAddTimer(runLoop, mOSTimer, kCFRunLoopCommonModes);
}

Timer_impl::~Timer_impl()
{
  Stop();
}

void Timer_impl::Stop()
{
  if (mOSTimer)
  {
    CFRunLoopTimerInvalidate(mOSTimer);
    CFRelease(mOSTimer);
    mOSTimer = nullptr;
  }
}

void Timer_impl::TimerProc(CFRunLoopTimerRef timer, void *info)
{
  Timer_impl* itimer = (Timer_impl*) info;
  itimer->mTimerFunc(*itimer);
}

#elif defined OS_WIN || (defined OS_LINUX && defined APP_API)

class Timer_impl : public Timer
{
public:
  Timer_impl(ITimerFunction func, uint32_t intervalMs);
  ~Timer_impl();
  void Stop() override;
  static void CALLBACK TimerProc(HWND hwnd, UINT uMsg, UINT_PTR idEvent, DWORD dwTime);

private:
  static WDL_Mutex sMutex;
  static WDL_PtrList<Timer_impl> sTimers;

  UINT_PTR ID = 0;
  ITimerFunction mTimerFunc;
  uint32_t mIntervalMs;
};


Timer* Timer::Create(ITimerFunction func, uint32_t intervalMs)
{
  return new Timer_impl(func, intervalMs);
}

WDL_Mutex Timer_impl::sMutex;
WDL_PtrList<Timer_impl> Timer_impl::sTimers;

Timer_impl::Timer_impl(ITimerFunction func, uint32_t intervalMs)
: mTimerFunc(func)
, mIntervalMs(intervalMs)

{
  ID = SetTimer(0, 0, intervalMs, TimerProc); //TODO: timer ID correct?

  if (ID)
  {
    WDL_MutexLock lock(&sMutex);
    sTimers.Add(this);
  }
}

Timer_impl::~Timer_impl()
{
  Stop();
}

void Timer_impl::Stop()
{
  if (ID)
  {
    KillTimer(0, ID);
    WDL_MutexLock lock(&sMutex);
    sTimers.DeletePtr(this);
    ID = 0;
  }
}

void CALLBACK Timer_impl::TimerProc(HWND hwnd, UINT uMsg, UINT_PTR idEvent, DWORD dwTime)
{
  WDL_MutexLock lock(&sMutex);

  for (auto i = 0; i < sTimers.GetSize(); i++)
  {
    Timer_impl* pTimer = sTimers.Get(i);

    if (pTimer->ID == idEvent)
    {
      pTimer->mTimerFunc(*pTimer);
      return;
    }
  }
}

#elif defined OS_LINUX
// other API on Linux do not support unrelated timers
class Timer_impl : public Timer
{
public:
  Timer_impl(ITimerFunction func, uint32_t intervalMs);
  ~Timer_impl();

  void Stop() override;
  static void NotifyCallback(union sigval v);


private:
  static WDL_Mutex sMutex;
  static WDL_PtrList<Timer_impl> sTimers;

#if IPLUG_EDITOR
  uint32_t mID;
#else
  timer_t mID;
#endif
  ITimerFunction mTimerFunc;
  uint32_t mIntervalMs;
};

WDL_Mutex Timer_impl::sMutex;
WDL_PtrList<Timer_impl> Timer_impl::sTimers;

Timer* Timer::Create(ITimerFunction func, uint32_t intervalMs)
{
  return new Timer_impl(func, intervalMs);
}

#if IPLUG_EDITOR
Timer_impl::Timer_impl(ITimerFunction func, uint32_t intervalMs)
: mTimerFunc(func)
, mIntervalMs(intervalMs)
, mID(0)
{
  auto cb = [&](uint64_t time) -> bool { mTimerFunc(*this); return true; };
  Task task = Task::FromMs(intervalMs, intervalMs, cb);
  mID = IPlugTaskThread::instance()->Push(std::move(task));
}

Timer_impl::~Timer_impl()
{
  Stop();
}

void Timer_impl::Stop()
{
  if (mID)
  {
    IPlugTaskThread::instance()->Cancel(mID);
    mID = 0;
  }
}

#else // No IPLUG_EDITOR
void Timer_impl::NotifyCallback(union sigval v)
{
  Timer_impl* timer = (Timer_impl*)v.sival_ptr;
  timer->mTimerFunc(*timer);
}

Timer_impl::Timer_impl(ITimerFunction func, uint32_t intervalMs)
: mTimerFunc(func)
, mIntervalMs(intervalMs)
, mID(0)
{
  int err;
  struct sigevent evt;
  evt.sigev_notify = SIGEV_THREAD;
  evt.sigev_signo = 0;
  evt.sigev_value.sival_ptr = this;
  evt.sigev_notify_function = &Timer_impl::NotifyCallback;
  evt.sigev_notify_attributes = nullptr;

  err = timer_create(CLOCK_MONOTONIC, &evt, &mID);
  if (err != 0)
  {
    mID = 0;
    return;
  }

  auto MakeTimespec = [](uint32_t ms) -> struct timespec {
    struct timespec t = { ms / 1000, (ms % 1000) * 1000000 }; return t;
  };

  struct itimerspec ntime;
  ntime.it_value = MakeTimespec(intervalMs);
  ntime.it_interval = MakeTimespec(intervalMs);
  err = timer_settime(mID, 0, &ntime, nullptr);
  if (err != 0)
  {
    timer_delete(mID);
    mID = 0;
    return;
  }

  WDL_MutexLock lock(&sMutex);
  sTimers.Add(this);
}

Timer_impl::~Timer_impl()
{
  Stop();
}

void Timer_impl::Stop()
{
  if (mID)
  {
    // NB. timer_delete returns an error code. Should we check it?
    timer_delete(mID);
    WDL_MutexLock lock(&sMutex);
    sTimers.DeletePtr(this);
    mID = 0;
  }
}
#endif // IPLUG_EDITOR

#elif defined OS_WEB
class Timer_impl : public Timer
{
public:
  Timer_impl(ITimerFunction func, uint32_t intervalMs);
  ~Timer_impl();
  void Stop() override;
  static void TimerProc(void *userData);

private:
  long ID = 0;
  ITimerFunction mTimerFunc;
};

Timer* Timer::Create(ITimerFunction func, uint32_t intervalMs)
{
  return new Timer_impl(func, intervalMs);
}

Timer_impl::Timer_impl(ITimerFunction func, uint32_t intervalMs)
: mTimerFunc(func)
{
  ID = emscripten_set_interval(TimerProc, intervalMs, this);
}

Timer_impl::~Timer_impl()
{
  Stop();
}

void Timer_impl::Stop()
{
  emscripten_clear_interval(ID);
}

void Timer_impl::TimerProc(void* userData)
{
  Timer_impl* itimer = (Timer_impl*) userData;
  itimer->mTimerFunc(*itimer);
}

#else
  #error NOT IMPLEMENTED
#endif
