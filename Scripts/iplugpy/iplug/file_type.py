from pathlib import Path

def guess_file_type(path: Path) -> str:
  ext = path.suffix
  if ext == ".ttf":
    return "font,ttf"
  elif ext == ".fon":
    return "font,fon"
  elif ext in (".png", ".gif", ".tiff"):
    return "image,raster"
  elif ext in (".svg"):
    return "image,vector"
  elif ext == ".ico":
    return "image,icon"
  elif ext == ".xib":
    return "xib,misc"
  elif ext in (".md"):
    return "text,markdown,doc"
  elif ext in (".txt"):
    return "text"
  elif ext in (".c", ".cpp", ".cxx", ".h", ".hpp", ".hxx"):
    return "text,code,cpp"
  elif ext in (".rs", ".lua", ".cmake", ".make", ".py", ".sh", ".bat", ".pl", ".php", ".rb"):
    return "text,code"
  elif ext in (".xml", ".storyboard"):
    return "text,xml"
  elif ext == ".plist":
    return "text,xml,plist"
  else:
    return "misc"
  
def cm_guess_file_types(inp_list: str):
  guesses = [guess_file_type(Path(p)) for p in inp_list.split(';')]
  # add commas before and after each entry for CMake
  guesses = [f',{g},' for g in guesses]
  print(';'.join(guesses))