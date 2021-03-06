# Fat Free CRM
# Copyright (C) 2008-2010 by Michael Dvorkin
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
# 
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#------------------------------------------------------------------------------

class LeadsController < ApplicationController
  before_filter :require_user
  before_filter :get_data_for_sidebar, :only => :index
  before_filter :set_current_tab, :only => [ :index, :show ]
  before_filter :auto_complete, :only => :auto_complete
  after_filter  :update_recently_viewed, :only => :show

  # GET /leads
  # GET /leads.xml                                                AJAX and HTML
  #----------------------------------------------------------------------------
  def index
    @leads = get_leads(:page => params[:page])

    respond_to do |format|
      format.html # index.html.erb
      format.js   # index.js.rjs
      format.xml  { render :xml => @leads }
    end
  end

  # GET /leads/1
  # GET /leads/1.xml                                                       HTML
  #----------------------------------------------------------------------------
  def show
    @lead = Lead.my(@current_user).find(params[:id])
    @comment = Comment.new

    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render :xml => @lead }
    end

  rescue ActiveRecord::RecordNotFound
    respond_to_not_found(:html, :xml)
  end

  # GET /leads/new
  # GET /leads/new.xml                                                     AJAX
  #----------------------------------------------------------------------------
  def new
    @lead = Lead.new(:access => Setting.default_access)
    @users = User.except(@current_user).all
    @campaigns = Campaign.my(@current_user).all(:order => "name")
    if params[:related]
      model, id = params[:related].split("_")
      instance_variable_set("@#{model}", model.classify.constantize.my(@current_user).find(id))
    end

    respond_to do |format|
      format.js   # new.js.rjs
      format.xml  { render :xml => @lead }
    end

  rescue ActiveRecord::RecordNotFound # Kicks in if related asset was not found.
    respond_to_related_not_found(model, :js) if model
  end

  # GET /leads/1/edit                                                      AJAX
  #----------------------------------------------------------------------------
  def edit
    @lead = Lead.my(@current_user).find(params[:id])
    @users = User.except(@current_user).all
    @campaigns = Campaign.my(@current_user).all(:order => "name")
    if params[:previous] =~ /(\d+)\z/
      @previous = Lead.my(@current_user).find($1)
    end

  rescue ActiveRecord::RecordNotFound
    @previous ||= $1.to_i
    respond_to_not_found(:js) unless @lead
  end

  # POST /leads
  # POST /leads.xml                                                        AJAX
  #----------------------------------------------------------------------------
  def create
    @lead = Lead.new(params[:lead])
    @users = User.except(@current_user).all
    @campaigns = Campaign.my(@current_user).all(:order => "name")

    respond_to do |format|
      if @lead.save_with_permissions(params)
        if called_from_index_page?
          @leads = get_leads
          get_data_for_sidebar
        else
          get_data_for_sidebar(:campaign)
        end
        format.js   # create.js.rjs
        format.xml  { render :xml => @lead, :status => :created, :location => @lead }
      else
        format.js   # create.js.rjs
        format.xml  { render :xml => @lead.errors, :status => :unprocessable_entity }
      end
    end
  end

  # PUT /leads/1
  # PUT /leads/1.xml
  #----------------------------------------------------------------------------
  def update
    @lead = Lead.my(@current_user).find(params[:id])

    respond_to do |format|
      if @lead.update_with_permissions(params[:lead], params[:users])
        update_sidebar
        format.js
        format.xml  { head :ok }
      else
        @users = User.except(@current_user).all
        @campaigns = Campaign.my(@current_user).all(:order => "name")
        format.js
        format.xml  { render :xml => @lead.errors, :status => :unprocessable_entity }
      end
    end

  rescue ActiveRecord::RecordNotFound
    respond_to_not_found(:js, :xml)
  end

  # DELETE /leads/1
  # DELETE /leads/1.xml                                           HTML and AJAX
  #----------------------------------------------------------------------------
  def destroy
    @lead = Lead.my(@current_user).find(params[:id])
    @lead.destroy if @lead

    respond_to do |format|
      format.html { respond_to_destroy(:html) }
      format.js   { respond_to_destroy(:ajax) }
      format.xml  { head :ok }
    end

  rescue ActiveRecord::RecordNotFound
    respond_to_not_found(:html, :js, :xml)
  end

  # GET /leads/1/convert
  # GET /leads/1/convert.xml                                               AJAX
  #----------------------------------------------------------------------------
  def convert
    @lead = Lead.my(@current_user).find(params[:id])
    @users = User.except(@current_user).all
    @account = Account.new(:user => @current_user, :name => @lead.company, :access => "Lead")
    @accounts = Account.my(@current_user).all(:order => "name")
    @opportunity = Opportunity.new(:user => @current_user, :access => "Lead", :stage => "prospecting", :campaign => @lead.campaign, :source => @lead.source)
    if params[:previous] =~ /(\d+)\z/
      @previous = Lead.my(@current_user).find($1)
    end

  rescue ActiveRecord::RecordNotFound
    @previous ||= $1.to_i
    respond_to_not_found(:js, :xml) unless @lead
  end

  # PUT /leads/1/promote
  # PUT /leads/1/promote.xml                                               AJAX
  #----------------------------------------------------------------------------
  def promote
    @lead = Lead.my(@current_user).find(params[:id])
    @users = User.except(@current_user).all
    @account, @opportunity, @contact = @lead.promote(params)
    @accounts = Account.my(@current_user).all(:order => "name")
    @stage = Setting.unroll(:opportunity_stage)

    respond_to do |format|
      if @account.errors.empty? && @opportunity.errors.empty? && @contact.errors.empty?
        @lead.convert
        update_sidebar
        format.js   # promote.js.rjs
        format.xml  { head :ok }
      else
        format.js   # promote.js.rjs
        format.xml  { render :xml => @account.errors + @opportunity.errors + @contact.errors, :status => :unprocessable_entity }
      end
    end

  rescue ActiveRecord::RecordNotFound
    respond_to_not_found(:js, :xml)
  end

  # PUT /leads/1/reject
  # PUT /leads/1/reject.xml                                       AJAX and HTML
  #----------------------------------------------------------------------------
  def reject
    @lead = Lead.my(@current_user).find(params[:id])
    @lead.reject if @lead
    update_sidebar

    respond_to do |format|
      format.html { flash[:notice] = t(:msg_asset_rejected, @lead.full_name); redirect_to(leads_path) }
      format.js   # reject.js.rjs
      format.xml  { head :ok }
    end

  rescue ActiveRecord::RecordNotFound
    respond_to_not_found(:html, :js, :xml)
  end

  # GET /leads/search/query                                                AJAX
  #----------------------------------------------------------------------------
  def search
    @leads = get_leads(:query => params[:query], :page => 1)

    respond_to do |format|
      format.js   { render :action => :index }
      format.xml  { render :xml => @leads.to_xml }
    end
  end

  # POST /leads/auto_complete/query                                        AJAX
  #----------------------------------------------------------------------------
  # Handled by before_filter :auto_complete, :only => :auto_complete

  # GET /leads/options                                                     AJAX
  #----------------------------------------------------------------------------
  def options
    unless params[:cancel].true?
      @per_page = @current_user.pref[:leads_per_page] || Lead.per_page
      @outline  = @current_user.pref[:leads_outline]  || Lead.outline
      @sort_by  = @current_user.pref[:leads_sort_by]  || Lead.sort_by
      @naming   = @current_user.pref[:leads_naming]   || Lead.first_name_position
    end
  end

  # POST /leads/redraw                                                     AJAX
  #----------------------------------------------------------------------------
  def redraw
    @current_user.pref[:leads_per_page] = params[:per_page] if params[:per_page]
    @current_user.pref[:leads_outline]  = params[:outline]  if params[:outline]

    # Sorting and naming only: set the same option for Contacts if the hasn't been set yet.
    if params[:sort_by]
      @current_user.pref[:leads_sort_by] = Lead::sort_by_map[params[:sort_by]]
      if Contact::sort_by_fields.include?(params[:sort_by])
        @current_user.pref[:contacts_sort_by] ||= Contact::sort_by_map[params[:sort_by]]
      end
    end
    if params[:naming]
      @current_user.pref[:leads_naming] = params[:naming]
      @current_user.pref[:contacts_naming] ||= params[:naming]
    end

    @leads = get_leads(:page => 1) # Start one the first page.
    render :action => :index
  end

  # POST /leads/filter                                                     AJAX
  #----------------------------------------------------------------------------
  def filter
    session[:filter_by_lead_status] = params[:status]
    @leads = get_leads(:page => 1) # Start one the first page.
    render :action => :index
  end

  private
  #----------------------------------------------------------------------------
  def get_leads(options = { :page => nil, :query => nil })
    self.current_page = options[:page] if options[:page]
    self.current_query = options[:query] if options[:query]

    records = {
      :user => @current_user,
      :order => @current_user.preference[:leads_sort_by] || Lead.sort_by
    }
    pages = {
      :page => current_page,
      :per_page => @current_user.preference[:leads_per_page]
    }

    # Call :get_leads hook and return its output if any.
    leads = hook(:get_leads, self, :records => records, :pages => pages)
    return leads.last unless leads.empty?

    # Default processing if no :get_leads hooks are present.
    if session[:filter_by_lead_status]
      filtered = session[:filter_by_lead_status].split(",")
      current_query.blank? ? Lead.my(records).only(filtered) : Lead.my(records).only(filtered).search(current_query)
    else
      current_query.blank? ? Lead.my(records) : Lead.my(records).search(current_query)
    end.paginate(pages)
  end

  #----------------------------------------------------------------------------
  def respond_to_destroy(method)
    if method == :ajax
      if called_from_index_page?                  # Called from Leads index.
        get_data_for_sidebar                      # Get data for the sidebar.
        @leads = get_leads                        # Get leads for current page.
        if @leads.blank?                          # If no lead on this page then try the previous one.
          @leads = get_leads(:page => current_page - 1) if current_page > 1
          render :action => :index and return     # And reload the whole list even if it's empty.
        end
      else                                        # Called from related asset.
        self.current_page = 1                     # Reset current page to 1 to make sure it stays valid.
        @campaign = @lead.campaign                # Reload lead's campaign if any.
      end                                         # Render destroy.js.rjs
    else # :html destroy
      self.current_page = 1
      flash[:notice] = t(:msg_asset_deleted, @lead.full_name)
      redirect_to(leads_path)
    end
  end

  #----------------------------------------------------------------------------
  def get_data_for_sidebar(related = false)
    if related
      instance_variable_set("@#{related}", @lead.send(related)) if called_from_landing_page?(related.to_s.pluralize)
    else
      @lead_status_total = { :all => Lead.my(@current_user).count, :other => 0 }
      Setting.lead_status.each do |key|
        @lead_status_total[key] = Lead.my(@current_user).count(:conditions => [ "status=?", key.to_s ])
        @lead_status_total[:other] -= @lead_status_total[key]
      end
      @lead_status_total[:other] += @lead_status_total[:all]
    end
  end

  #----------------------------------------------------------------------------
  def update_sidebar
    if called_from_index_page?
      get_data_for_sidebar
    else
      get_data_for_sidebar(:campaign)
    end
  end

end
