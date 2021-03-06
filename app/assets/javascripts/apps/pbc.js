//= require can.jquery-all
//= require pbc/responses_controller
//= require pbc/modals_controller
//= require pbc/system

(function(namespace, $) {

    if(namespace.location.pathname.indexOf("/pbc_lists") < 0)
        return;

function escapeHTML(s) {
  if (typeof(s)=='string') {
    s = s
      .replace(/'/g,'&#39;')
      .replace(/\"/g,'&quot;')
      .replace(/</g,'&lt;')
      .replace(/>/g,'&gt;');
  }
  return s;
}

$.widget(
    "pbc.autocomplete"
    , $.ui.autocomplete
    , {
        options : {
            minLength: 1
            , source: CMS.Models.System.search
            , focus: function( event, ui ) {
                //$( "#project" ).val( ui.item.label );
                return false;
            }
            , select: function( event, ui ) {
                var $this = $(this)
                  , resp = new CMS.Models.Response();
                resp.attr({
                    request_id : $(event.target).closest("[data-filter-id]").data("filter-id")
                    , system_id : ui.item.value
                });
                resp.
                  save().
                  then(function(){ $this.val(""); });

                $this.closest('.collapse').collapse('hide');
                $this.val('');
                return false;
            }
            , open: function() {
                $( this ).removeClass( "ui-corner-all" ).addClass( "ui-corner-top" );
            }
            , close: function() {
                $( this ).removeClass( "ui-corner-top" ).addClass( "ui-corner-all" );
            }
        }
        , _renderItem : function( ul, item ) {
            return $( "<li class='something'>" )
                .data( "item.autocomplete", item )
                .append( "<a>"+ escapeHTML(item.label) + "</a>" )
                .appendTo( ul );
        }
    }
);
$.widget.bridge("pbc_autocomplete", $.pbc.autocomplete);

$.widget(
  "pbc.autocomplete_people"
  , $.pbc.autocomplete
  , { options : {
      source : CMS.Models.Person.search
      , select :  function(event, ui) {
        $(event.target).trigger("personSelected", ui.item);
        $(this).data("pbcAutocomplete_people")._value("");
        return false;
      }
      , search : function(event) {

      }
  }
  , _renderItem : function(ul, item) {
    var label = item.name ? item.name + " (" + item.label + ")" : item.label;
    return $( "<li class='inline-search-result'>" )
        .data( "item.autocomplete", item )
        .append( "<a>" + escapeHTML(label) + "</a>" )
        .appendTo( ul );
  }
  });
$.widget.bridge("pbc_autocomplete_people", $.pbc.autocomplete_people);

$.widget(
  "pbc.autocomplete_documents"
  , $.pbc.autocomplete
  , { options : {
      source : CMS.Models.Document.search
      , select :  function(event, ui) {
        if(ui.item.id !== null) {
          $(event.target).trigger("documentSelected", ui.item);
        }
        return false;
      }
      , search : function(event) {

      }
      , response : function(event, data) {
        if(!data.content.length) {
          data.content.push(
            {link_url : "There is no Doc or URL in the system that matches your search. "
            , id : null });
          data.content.push(
            {link_url : "Please create a new reference by pushing the + icon to the right"
            , id : null})
          $(event.target).addClass("error-input");
        } else {
          $(event.target).removeClass("error-input");
        }
      }
  }
  , _renderItem : function(ul, item) {
    var label;
    if (item.title) {
      label = "" + item.title + (item.link_url ? " (" + item.link_url + ")" : "");
    } else {
      label = item.link_url;
    }
    return $( "<li class='inline-search-result'>" )
        .addClass(item.id ? "" : "error")
        .data( "item.autocomplete", item )
        .append( "<a>" + escapeHTML(label) + "</a>" )
        .appendTo( ul );
  }
  });
$.widget.bridge("pbc_autocomplete_documents", $.pbc.autocomplete_documents);

$(function() {
    // Trigger controller load when collapsed container is expanded
    $(document.body).on("click", ".pbc-requests .pbc-item-head .openclose", function(ev) {
        var filter_element = $(ev.currentTarget).closest("[data-filter-id]")
        $(ev.currentTarget).closest(".main-item").find(".pbc-responses").cms_controllers_responses({id : filter_element.data("filter-id"), type_id : filter_element.data("filter-type-id"), type_name : filter_element.data("filter-type-name")});
    });

    $(".pbc-system-search").pbc_autocomplete();

    // Using rotate_flow_control_assessment route
    $('body').on('ajax:success', 'a.rotate_control_assessment', function(data) {
      var $this = $(this)
        , $icon = $this.find('i')
        ;

      if ($this.hasClass('btn-success')) {
        // success state -> blank state
        $this.removeClass('btn-success');
        $icon.removeClass('grcicon-check-white').addClass('grcicon-blank');
      } else if ($this.hasClass('btn-warning')) {
        // failure state -> success state
        $this.removeClass('btn-warning').addClass('btn-success');
        $icon.removeClass('grcicon-x-white').addClass('grcicon-check-white');
      } else {
        // blank state -> failure state
        $this.addClass('btn-warning');
        $icon.removeClass('grcicon-blank').addClass('grcicon-x-white');
      }
    });

    $(document.body).cms_controllers_pbc_modals({});
});

})(this, can.$);
