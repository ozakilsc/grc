//= require can.jquery-all
//= require pbc/system
//= require pbc/population_sample
//= require pbc/meeting

//Response isn't technically a System, but subclassing makes it much easier to do the binding of 
// created/destroeyd listeners on ObjectDocuments and ObjectPeople, which both classes use.
CMS.Models.System("CMS.Models.Response", {

    root_object : "response"
    , xable_type : "Response"
    , init : function() {
      this._super && this._super.apply(this, arguments);

      this.cache = {}; //override System cache

      CMS.Models.Meeting.bind("destroyed", function(ev, mtg){
        can.each(CMS.Models.Response.cache, function(response) {
          response.removeElementFromChildList("meetings", mtg);
        });
      });
    }
    , create : function(params) {
        var _params = { response : {
            system_id : params.system_id
            , request_id : params.request_id
        }}
        return $.ajax({
                type : "POST"
                , url : "/responses.json"
                , dataType : "json"
                , data : _params
            })
    }
    , update : function(id, params) {
        var _params = this.process_args(params);
        return $.ajax({
                type : "PUT"
                , url : "/responses/" + id + ".json"
                , dataType : "json"
                , data : _params
            })
    }

    , findAll : "GET /responses.json"
    , destroy : "DELETE /responses/{id}.json"
}, {

    init : function() {
        this._super();

        function reinit() {
            this.attr("system", new CMS.Models.System(this.system ? this.system.serialize() : {}));
            this.attr(
              "population_sample"
              , new CMS.Models.PopulationSample(
                  this.population_sample && this.population_sample.serialize 
                  ? this.population_sample.serialize() 
                  : this.population_sample
            ));
            var mtgs = new can.Model.List();
            can.each(this.attr("meetings"), function(val) {
              mtgs.push(new CMS.Models.Meeting(val.serialize ? val.serialize() : val));
            });
            this.attr("meetings", mtgs);
        }

        this.bind("created", can.proxy(reinit, this));

        reinit.call(this);
    }

});