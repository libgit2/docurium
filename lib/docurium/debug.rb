$debug_stack = [false]

def debug_enabled
  $debug_stack[-1]
end

def debug(str = nil)
  puts str if debug_enabled
end

def debug_enable
  $debug_stack.push true
end

def debug_silence
  $debug_stack.push false
end

def debug_set val
  $debug_stack.push val
end

def debug_pass
  $debug_stack.push debug_enabled
end

def debug_restore
  $debug_stack.pop
end

def with_debug(&block)
  debug_enable
  block.call
  debug_restore
end

def without_debug(&block)
  debug_silence
  block.call
  debug_restore
end