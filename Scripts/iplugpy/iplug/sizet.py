from typing import NamedTuple, Any
import re

SIZE_SPLIT_REG = re.compile(r'([0-9]+)([xX,][0-9]+)?', re.ASCII)

class SizeT(NamedTuple):
  """Represents a size."""
  w: int
  h: int

  def __gt__(self, value: Any) -> bool:
    cw, ch = self.compare(value)
    return cw > 0 and ch > 0
    
  def __lt__(self, value: Any) -> bool:
    cw, ch = self.compare(value)
    return cw < 0 and ch < 0
  
  def __eq__(self, value: Any) -> bool:
    cw, ch = self.compare(value)
    return cw == 0 and ch == 0
  
  def __le__(self, value: Any) -> bool:
    cw, ch = self.compare(value)
    return cw <= 0 and ch <= 0
  
  def __ge__(self, value: Any) -> bool:
    cw, ch = self.compare(value)
    return cw >= 0 and ch >= 0
  
  def __add__(self, rhs: Any) -> 'SizeT':
    w2, h2 = SizeT._get_rvalues(rhs)
    return SizeT(self.w + w2, self.h + h2)
  
  def __sub__(self, rhs: Any) -> 'SizeT':
    w2, h2 = SizeT._get_rvalues(rhs)
    return SizeT(self.w - w2, self.h - h2)
  
  @staticmethod
  def _get_rvalues(rhs: 'SizeT|int|float') -> 'tuple[int, int]':
    try:
      f = int(rhs) # type: ignore
      return (f, f)
    except:
      w, h = rhs # type: ignore
      return (int(w), int(h))
  
  def compare(self, other: 'tuple[int, ...]') -> 'tuple[int, int]':
    vw, vh = other
    return (self.w - vw, self.h - vh)
  
  def ratio(self) -> float:
    return float(self.w) / float(self.h)
  
  def scale_factor_to(self, other: 'SizeT') -> float:
    """
    Returns the smallest multiplier needed to make either
    ``self.w == other.w`` or ``self.h == other.h``.
    """
    ratio_diff = self.ratio() - other.ratio()
    if ratio_diff >= 0:
      # Source is wider or same ratio, scale height to match
      return float(other.h) / float(self.h)
    else:
      # Source is taller, scale width to match
      return float(other.w) / float(self.w)
    
  def __str__(self) -> str:
    return f'{self.w}x{self.h}'

  @staticmethod
  def parse(s: str) -> 'SizeT':
    m = SIZE_SPLIT_REG.fullmatch(s)
    if not m:
      raise ValueError(f'Cannot parse size "{s}"')
    w_str = m.group(1)
    h_str = m.group(2)
    size_w = int(w_str)
    size_h = int(h_str[1:]) if h_str else size_w
    return SizeT(size_w, size_h)
  