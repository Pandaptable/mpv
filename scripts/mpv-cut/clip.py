import sys
import uuid

sig = b'uuid'+uuid.UUID("a1c85299-3346-4db8-88f0-83f57a75a5ef").bytes

with open(sys.argv[1], 'rb') as f:
  with open(sys.argv[2], 'ab') as target:
    target.write(sig+f.read().split(sig, 1)[1])