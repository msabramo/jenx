#
#  JenxConnectionManager.rb
#  jenx
#
#  Created by Trent Kocurek on 5/23/11.
#  Copyright 2011 Urban Coding. Released under the MIT license.
#

class JenxConnectionManager
    def initialize(&block)
        @queue ||= Dispatch::Queue.new("com.urbancoding.jenx")
        @group = Dispatch::Group.new

        NSLog "JenxConnectionManager.initialize calling async..."
        @queue.async(@group) { @value = block.call }
        NSLog "JenxConnectionManager.initialize @value = #{@value.inspect}"
    end
    
    def value
        NSLog ".value waiting..."
        @group.wait(5)
        NSLog ".value about to return @value = #{@value.inspect}"
        @value
    end
end