/*
 ==============================================================================

 This file is part of the iPlug 2 library. Copyright (C) the iPlug 2 developers.

 See LICENSE.txt for  more info.

 ==============================================================================
*/


#pragma once

/** @file
 * @brief This file includes classes for implementing timers - in order to get a regular callback on the main thread
 * The interface is partially based on the api of Steinberg's timer.cpp from the VST3_SDK for compatibility,
 * rewritten using SWELL: base/source/timer.cpp, so thanks to them
*/

#include <stdint.h>
#include <functional>
#include "IPlugPlatform.h"

BEGIN_IPLUG_NAMESPACE

/** Base class for timer */
struct Timer
{
  Timer() = default;
  Timer(const Timer&) = delete;
  Timer& operator=(const Timer&) = delete;

  using ITimerFunction = std::function<void(Timer& t)>;

  static Timer* Create(ITimerFunction func, uint32_t intervalMs);

  virtual ~Timer() {};
  virtual void Stop() = 0;
};

END_IPLUG_NAMESPACE
