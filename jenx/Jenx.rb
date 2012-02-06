#
#  Jenx.rb
#  jenx
#
#  Created by Trent Kocurek on 5/18/11.
#  Copyright 2011 Urban Coding. Released under the MIT license.
#

class Jenx
    attr_accessor :menu
    attr_accessor :menu_jenx_status
    attr_accessor :menu_default_project
    attr_accessor :menu_default_project_status
    attr_accessor :menu_default_project_update_time
    
    def awakeFromNib
        JenxPreferences::setup_defaults
        initialize_menu_ui_items
        register_observers
        
        @old_default_build_status = ''
        @new_default_build_status = ''
        @old_sub_build_statuses   = {}
        @new_sub_build_statuses   = {}
        
        #Uncomment the following line to clear NSUserDefaults on each run.
        #Testing purposes only.
        #clear_nsdefaults
    end
    
    def applicationDidFinishLaunching(notification)
        @initial_load = true
        @editing_preferences = false
        
        init_jenx
    end
    
    def init_jenx(sender=nil)
        @prefs = JenxPreferences.sharedInstance
        @project_menu_count = @prefs.num_menu_projects
        @growl_center = JenxNotificationCenter.new(@prefs)
        
        if @prefs.are_invalid?
            NSLog("showing preferences because invalid")
            show_preferences_window(nil)
        else
            ensure_connection
        end
    end
    
    def ensure_connection(sender=nil)
        if @refresh_timer.nil? || !@refresh_timer.isValid
            create_timer
        end

        fetch_current_build_status
    end
    
    def fetch_current_build_status
        @old_default_build_status = @new_default_build_status
        NSLog("fetching current build status for #{@prefs.num_menu_projects} projects from #{@prefs.build_server_url}...")
        jenx_request = JenxRequest.new(@prefs.build_server_url + JENX_API_URI, method(:process_build_status))
        jenx_request.perform_request
    end

    def process_build_status(all_projects)
        NSLog("process_build_status called with #{all_projects.length} projects.")
        @all_projects = all_projects
        performSelector "update_ui", withObject:nil, waitUntilDone:false
        NSLog("process_build_status DONE with #{all_projects.length} projects.")
    end

    def update_ui
        default_project_status_color = ''
        @all_projects['jobs'].find {|p| default_project_status_color = p['color'] if p['name'].downcase.eql?(@prefs.default_project.downcase)}
        @new_default_build_status = get_current_status_for(default_project_status_color)
        
        jenx_status_item = @jenx_item.menu.itemAtIndex(0)
        jenx_status_item.setTitle(CONNECTED)
        
        # @menu_default_project.setTitle(localize_format("Project: %@", "#{@prefs.default_project}"))
        @menu_default_project.setTitle(localize("Project: ") + @prefs.default_project)

        # @menu_default_project_status.setTitle(localize_format("Status: %@", "#{@new_default_build_status}"))
        @menu_default_project_status.setTitle(localize("Status: ") + @new_default_build_status)

        date = Time.now.strftime(localize("%I:%M:%S %p", "%I:%M:%S %p"))
        @menu_default_project_update_time.setTitle(localize("Last Update: ") + date)
        NSLog("Set last update time to #{date}")
        
        @jenx_item.setImage(get_current_status_icon_for(default_project_status_color, nil))

        NSLog("update_ui: Calling load_projects...")
        load_projects
        NSLog("update_ui: Called load_projects (DONE).")
        NSLog("update_ui DONE")
    rescue Exception => e
        NSLog("error fetching build status: #{e.message}...")
    end
    
    def load_projects
        @old_sub_build_statuses = @new_sub_build_statuses
        if @initial_load
            NSLog("initial load of project menu items with #{@project_menu_count} projects...")
            @all_projects['jobs'].each_with_index do |project, index|
                if index < @project_menu_count
                    @jenx_item.menu.insertItem(project_menu_item(project, index), atIndex:index + JENX_STARTING_PROJECT_MENU_INDEX)
                end
            end
            
            growl_initial_status
            
            @jenx_item.menu.insertItem(view_all_menu_item(@project_menu_count), atIndex:@project_menu_count + JENX_STARTING_PROJECT_MENU_INDEX)
            
            @initial_load = false
        else
            NSLog("refreshing project menu items...")
            
            @all_projects['jobs'].each_with_index do |project, index|
                NSLog "Updating project menu item - project = \"#{project}\"; index = #{index}"
                if index < @project_menu_count
                    project_menu_item = @jenx_item.menu.itemAtIndex(index + JENX_STARTING_PROJECT_MENU_INDEX)
                    NSLog "project_menu_item = #{project_menu_item}"
                    project_menu_item.setImage(get_current_status_icon_for(project['color'], project_menu_item.image.name)) 
                end
            end

            NSLog("DONE refreshing project menu items...")
        end
        
        NSLog("Calling growl_update_status...")
        growl_update_status
        NSLog("Called growl_update_status (DONE).")
        NSLog("load_projects (DONE).")
    end
    
    def handle_broken_connection(error_type)
        # Comment out invalidate to fix issue GH-8
        # @refresh_timer.invalidate
        NSLog("#{CONNECTION_ERROR_TITLE}: #{error_type}")
        @jenx_item.setImage(@build_failure_icon)
        
        jenx_status_item = @jenx_item.menu.itemAtIndex(0)
    
        jenx_status_item.setTitle(CANNOT_CONNECT)
        jenx_status_item.setToolTip(CANNOT_CONNECT)
        @growl_center.notify(CONNECTION_ERROR_TITLE, CONNECTION_ERROR_MESSAGE, nil, CONNECTION_FAILURE)
        
        clear_projects_from_menu
    end
    
    def clear_projects_from_menu
        NSLog("clearing #{@project_menu_count} items from the menu if they exist...")
        
        begin
            for i in 1..@project_menu_count + 1
                @jenx_item.menu.removeItem(@jenx_item.menu.itemWithTag(i)) if @jenx_item.menu.itemWithTag(i)
            end
        rescue Exception => e
            NSLog(e.message)
        end
        
        NSLog("finished clearing")
    end
    
    def create_timer
        time = @prefs.refresh_time == 0 ? 5 : @prefs.refresh_time
        
        NSLog("create timer with refresh time of: #{time.to_s} seconds...")
        
        @refresh_timer = NSTimer.timerWithTimeInterval time,
            target:self, selector:"init_jenx:", userInfo:nil, repeats:true
        NSRunLoop.currentRunLoop.addTimer @refresh_timer, forMode:NSRunLoopCommonModes
    end
    
    def update_for_preferences(sender)
        NSLog("preferences saved, recreating timer...")
        @editing_preferences = false
        @initial_load = true
        
        init_jenx
    end
    
    def open_web_interface_for(sender)
        project_url = NSURL.alloc.initWithString(sender.toolTip)
        workspace = NSWorkspace.sharedWorkspace
        workspace.openURL(project_url)
    end
    
    def show_preferences_window(sender)
        @editing_preferences = true
        
        # clear_projects_from_menu
        NSApplication.sharedApplication.activateIgnoringOtherApps(true)
        PreferencesController.sharedController.showWindow(sender)
    end
    
    def initialize_menu_ui_items
        @app_icon = NSImage.imageNamed('app.tiff')
        @connecting_icon = NSImage.imageNamed('connecting.tiff')
        
        @build_success_icon = NSImage.imageNamed('build_success.tiff')
        @build_failure_icon = NSImage.imageNamed('build_failure.tiff')
        @build_initiated_icon = NSImage.imageNamed('build_initiated.tiff')
        
        @jenx_success = NSImage.imageNamed('jenx_success.tiff')
        @jenx_failure = NSImage.imageNamed('jenx_failure.tiff')
        @jenx_issues = NSImage.imageNamed('jenx_issues.tiff')
        
        @status_bar = NSStatusBar.systemStatusBar
        @jenx_item = @status_bar.statusItemWithLength(NSVariableStatusItemLength)
        @jenx_item.setHighlightMode(true)
        @jenx_item.setMenu(@menu)
        @jenx_item.setImage(@connecting_icon)
        
        jenx_status_item = @jenx_item.menu.itemAtIndex(0)
        jenx_status_item.setTitle(CONNECTED)
        
        @menu_default_project.setTitle(localize("Project: ..."))
        @menu_default_project_status.setTitle(localize("Status: ..."))
        @menu_default_project_update_time.setTitle(localize("Last Update: ..."))
    end

    def register_observers
        notification_center = NSNotificationCenter.defaultCenter
        
        notification_center.addObserver(
           self,
           selector:"update_for_preferences:",
           name:NOTIFICATION_PREFERENCES_UPDATED,
           object:nil
        )
    end

    def get_job_url_for(project)
        "#{@prefs.build_server_url}/job/#{project}"
    end

    def get_current_status_icon_for(color, current_image)
        case color.to_sym
            when :red
                @build_failure_icon
            when :blue_anime
                @build_initiated_icon
            else
                @app_icon
        end
    end
    
    def get_current_status_for(color)
        if @prefs.default_project.empty?
            "No default project set"
        end
        
        case color.to_sym
            when ""
                localize("Could not retrieve status")
            when :red
                localize("Broken")
            when :blue_anime
                localize("Building")
            else
                localize("Stable")
        end
    end
    
    def growl_initial_status
        passing_count = @new_sub_build_statuses.count - @new_sub_build_statuses.delete_if {|k,v| v != "red"}.count
        notify_message = "#{passing_count} of #{@project_menu_count} other projects are passing."
        case @new_default_build_status
            when "Stable"
                @growl_center.notify("#{@prefs.default_project} is passing!", notify_message, @jenx_success, BUILD_SUCCESS)
            when "Broken"
                @growl_center.notify("#{@prefs.default_project} is failing!", notify_message, @jenx_failure, BUILD_FAILURE)
            else
                @growl_center.notify("#{@prefs.default_project} is busy..", notify_message, @jenx_issues, BUILD_ISSUES)
        end
    end
    
    def growl_update_status
        if @new_sub_build_statuses.delete_if {|k, v| @old_sub_build_statuses[k] == v}.count > 0 || @old_default_build_status != @new_default_build_status
            passing_count = @new_sub_build_statuses.count - @new_sub_build_statuses.delete_if {|k,v| v != "red"}.count
            notify_message = "#{passing_count} of #{@project_menu_count} other projects are passing."
            case @default_project_current_status
                when "Stable"
                    @growl_center.notify("#{@prefs.default_project} is passing!", notify_message, @jenx_success, BUILD_SUCCESS)
                when "Broken"
                    @growl_center.notify("#{@prefs.default_project} is failing!", notify_message, @jenx_failure, BUILD_FAILURE)
                else
                    @growl_center.notify("#{@prefs.default_project} is busy..", notify_message, @jenx_issues, BUILD_ISSUES)
            end
        end
    end

    def project_menu_item(project, index)
        @new_sub_build_statuses[project['name']] = project['color']
        
        project_menu_item = NSMenuItem.alloc.init
        project_menu_item.setTitle(" #{project['name']}")
        project_menu_item.setToolTip(get_job_url_for(project['name']))
        project_menu_item.setEnabled(true)
        project_menu_item.setIndentationLevel(1)
        project_menu_item.setImage(get_current_status_icon_for(project['color'], nil))
        project_menu_item.setAction("open_web_interface_for:")
        project_menu_item.setTag(index + 1)
    end

    def view_all_menu_item(project_menu_count)
        view_all_menu_item = NSMenuItem.alloc.init
        view_all_menu_item.setTitle(localize("View all projects.."))
        view_all_menu_item.setToolTip(@prefs.build_server_url)
        view_all_menu_item.setIndentationLevel(1)
        view_all_menu_item.setAction("open_web_interface_for:")
        view_all_menu_item.setTag(project_menu_count + 1)
    end
    
    #testing purposes only
    def clear_nsdefaults
        NSUserDefaults.standardUserDefaults.removeObjectForKey(PREFERENCES_TOTAL_NUM_PROJECTS)
        NSUserDefaults.standardUserDefaults.removeObjectForKey(PREFERENCES_BUILD_SERVER_URL)
        NSUserDefaults.standardUserDefaults.removeObjectForKey(PREFERENCES_BUILD_SERVER_USERNAME)
        NSUserDefaults.standardUserDefaults.removeObjectForKey(PREFERENCES_BUILD_SERVER_PASSWORD)
        NSUserDefaults.standardUserDefaults.removeObjectForKey(PREFERENCES_DEFAULT_PROJECT)
        NSUserDefaults.standardUserDefaults.removeObjectForKey(PREFERENCES_REFRESH_TIME_INTERVAL)
        NSUserDefaults.standardUserDefaults.removeObjectForKey(PREFERENCES_MAX_PROJECTS_TO_SHOW)
    end
end
