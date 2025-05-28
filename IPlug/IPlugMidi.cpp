#include "IPlugMidi.h"

const char* iplug::IMidiMsg::StatusMsgStr(EStatusMsg msg)
{
  switch (msg)
  {
    case kNone: return "none";
    case kNoteOff: return "noteoff";
    case kNoteOn: return "noteon";
    case kPolyAftertouch: return "aftertouch";
    case kControlChange: return "controlchange";
    case kProgramChange: return "programchange";
    case kChannelAftertouch: return "channelaftertouch";
    case kPitchWheel: return "pitchwheel";
    default:  return "unknown";
  };
}

const char* iplug::IMidiMsg::CCNameStr(int idx)
{
  static const char* ccNameStrs[128] =
  {
    "BankSel.MSB",
    "Modulation",
    "BreathCtrl",
    "Contr. 3",
    "Foot Ctrl",
    "Porta.Time",
    "DataEntMSB",
    "MainVolume",
    "Balance",
    "Contr. 9",
    "Pan",
    "Expression",
    "FXControl1",
    "FXControl2",
    "Contr. 14",
    "Contr. 15",
    "Gen.Purp.1",
    "Gen.Purp.2",
    "Gen.Purp.3",
    "Gen.Purp.4",
    "Contr. 20",
    "Contr. 21",
    "Contr. 22",
    "Contr. 23",
    "Contr. 24",
    "Contr. 25",
    "Contr. 26",
    "Contr. 27",
    "Contr. 28",
    "Contr. 29",
    "Contr. 30",
    "Contr. 31",
    "BankSel.LSB",
    "Modul. LSB",
    "BrthCt LSB",
    "Contr. 35",
    "FootCt LSB",
    "Port.T LSB",
    "DataEntLSB",
    "MainVolLSB",
    "BalanceLSB",
    "Contr. 41",
    "Pan LSB",
    "Expr. LSB",
    "Contr. 44",
    "Contr. 45",
    "Contr. 46",
    "Contr. 47",
    "Gen.P.1LSB",
    "Gen.P.2LSB",
    "Gen.P.3LSB",
    "Gen.P.4LSB",
    "Contr. 52",
    "Contr. 53",
    "Contr. 54",
    "Contr. 55",
    "Contr. 56",
    "Contr. 57",
    "Contr. 58",
    "Contr. 59",
    "Contr. 60",
    "Contr. 61",
    "Contr. 62",
    "Contr. 63",
    "Damper Ped",
    "Porta. Ped",
    "Sostenuto ",
    "Soft Pedal",
    "Legato Sw",
    "Hold 2",
    "SoundCont 1",
    "SoundCont 2",
    "SoundCont 3",
    "SoundCont 4",
    "SoundCont 5",
    "SoundCont 6",
    "SoundCont 7",
    "SoundCont 8",
    "SoundCont 9",
    "SoundCont 10",
    "Gen.Purp.5",
    "Gen.Purp.6",
    "Gen.Purp.7",
    "Gen.Purp.8",
    "Portamento",
    "Contr. 85",
    "Contr. 86",
    "Contr. 87",
    "Contr. 88",
    "Contr. 89",
    "Contr. 90",
    "FX 1 Depth",
    "FX 2 Depth",
    "FX 3 Depth",
    "FX 4 Depth",
    "FX 5 Depth",
    "Data Incr",
    "Data Decr",
    "Non-RegLSB",
    "Non-RegMSB",
    "Reg LSB",
    "Reg MSB",
    "Contr. 102",
    "Contr. 103",
    "Contr. 104",
    "Contr. 105",
    "Contr. 106",
    "Contr. 107",
    "Contr. 108",
    "Contr. 109",
    "Contr. 110",
    "Contr. 111",
    "Contr. 112",
    "Contr. 113",
    "Contr. 114",
    "Contr. 115",
    "Contr. 116",
    "Contr. 117",
    "Contr. 118",
    "Contr. 119",
    "Contr. 120",
    "Reset Ctrl",
    "Local Ctrl",
    "AllNoteOff",
    "OmniModOff",
    "OmniModeOn",
    "MonoModeOn",
    "PolyModeOn"
  };
  if (idx < 128)
  {
    return ccNameStrs[idx];
  }
  else
  {
    return nullptr;
  }
}

/** Log a message (TRACER BUILDS) */
void iplug::IMidiMsg::LogMsg()
{
  Trace(TRACELOC, "midi:(%s:%d:%d:%d)", StatusMsgStr(StatusMsg()), Channel(), mData1, mData2);
}

/** Print a message (DEBUG BUILDS) */
void iplug::IMidiMsg::PrintMsg() const
{
  DBGMSG("midi: offset %i, (%s:%d:%d:%d)\n", mOffset, StatusMsgStr(StatusMsg()), Channel(), mData1, mData2);
}

char* iplug::ISysEx::SysExStr(char* str, int maxLen, const uint8_t* pData, int size)
{
  assert(str != NULL && maxLen >= 3);

  if (!pData || !size) {
    *str = '\0';
    return str;
  }

  char* pStr = str;
  int n = maxLen / 3;
  if (n > size) n = size;
  for (int i = 0; i < n; ++i, ++pData) {
    snprintf(pStr, maxLen, "%02X", (int)*pData);
    pStr += 2;
    *pStr++ = ' ';
  }
  *--pStr = '\0';

  return str;
}

/** Log a message (TRACER BUILDS) */
void iplug::ISysEx::LogMsg()
{
  char str[96];
  Trace(TRACELOC, "sysex:(%d:%s)", mSize, SysExStr(str, sizeof(str), mData, mSize));
}
