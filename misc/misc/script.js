$(window).on('load', function(){
    $('#loader').fadeOut(300);
})

$(window).on('beforeunload', function(){
    $('#loader').fadeIn(300);
})

$(document).ready(function(){
    
	var dropZone = $('#upload-container');

	$('#file-input').focus(function() {
		$('label[for=file-input]').addClass('focus');
	})
	.focusout(function() {
		$('label[for=file-input]').removeClass('focus');
	});


	dropZone.on('drag dragstart dragend dragover dragenter dragleave drop', function(){
		return false;
	});

	dropZone.on('dragover dragenter', function() {
		dropZone.addClass('dragover');
	});

	dropZone.on('dragleave', function(e) {
		let dx = e.pageX - dropZone.offset().left;
		let dy = e.pageY - dropZone.offset().top;
		if ((dx < 0) || (dx > dropZone.width()) || (dy < 0) || (dy > dropZone.height())) {
			dropZone.removeClass('dragover');
		}
	});

	dropZone.on('drop', function(e) {
		dropZone.removeClass('dragover');
		let files = e.originalEvent.dataTransfer.files;
        if (event.dataTransfer.files.length > 1) {
            alert('Нельзя загрузить больше одного файла!');
            return
        }
        $('#file-input')[0].files = files;
        $('#file-input-text').html(files[0].name);
        $('#upload-container').submit();
  	});

	$('#file-input').change(function() {
		let files = this.files;
        $('#file-input-text').html(files[0].name);
	});
    
    $("input:checkbox").on('click', function(e){
        if ($("input:checkbox:checked").length == 0) {
            e.preventDefault();
            alert('Нужно вырать хотя бы один язык!');
        } else {
            let value = "";
            $("input:checkbox:checked").each(function(){
                value += "+" + $(this).val();
            });
            value = value.substring(1);
            $("input:text[name=params]").val("");
            $("input:text[name=params]").val("-l "+value);
        }
    });
    
    let value = "";
    $("input:checkbox:checked").each(function(){
    value += "+" + $(this).val();
    });
    value = value.substring(1);
    $("input:text[name=params]").val("");
    $("input:text[name=params]").val("-l "+value);
    
});

