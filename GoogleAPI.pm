#Обёртка для работы с API гугль сервиса подсказок мест: https://developers.google.com/places/web-service/autocomplete
package GoogleAPI;
{
  use strict;
  use utf8;
  use LWP::UserAgent;
  use JSON;
  use Encode;
  
  #Отображение типов регионов, используемых в тестах, на типы, используемые гуглом
  my %RegionTypes = 
  (
    "обл" => [ "область" ],
    "Респ" => [ "республика" ],
    "АО" => [ "автономный округ" ],
    "Аобл" => [ "автономная область" ],
    "г" => [ "город" ],
  );
  
  #Отображение типов городов, используемых в тестах, на типы, используемые гуглом
  my %CityTypes = 
  (
    "г" => [ "город" ],
  );
  
  #Отображение типов улиц, используемых в тестах, на типы, используемые гуглом
  my %StreetTypes =
  (
    "ул" => [ "улица" ],
    "пер" => [ "переулок" ],
    "пр" => [ "проезд" ],
    "пр-кт" => [ "проспект" ],
    "ш" => [ "шоссе" ],
    "пл" => [ "площадь" ],
  );

  #Конструирует объект
  sub new( $$ )
  {
    my ( $class, $Token ) = @_;
    
    my $self = 
    { 
      user_agent => LWP::UserAgent->new( agent => "Mozilla/5.0 (Windows NT 6.1; WOW64; rv:51.0) Gecko/20100101 Firefox/51.0", timeout => 600, keep_alive => 10 ),
      
      token => $Token
    };

    bless( $self, $class );

    return $self;    
  }
  
  #Отсылает HTTP-запрос сервису для получения подсказок по заданному префиксу
  #Должен вернуть объектную обёртку поверх JSON-ответа
  sub RequestSuggestions( $$ )
  {
    my ( $self, $Prefix ) = @_;
    
    my $Token = $self->{token};
    
    my $Result = undef;
    
    my $Request = HTTP::Request->new( 'GET', "https://maps.googleapis.com/maps/api/place/autocomplete/json?components=country:ru&language=ru&key=$Token&input=$Prefix&" );
    $Request->header( 'Referer' => 'https://google-developers.appspot.com/places/javascript/demos/placeautocomplete/placeautocomplete' );
    
    my $Response = $self->{ user_agent }->request( $Request );
    
    if( defined($Response) && $Response->is_success() )
    {
      $Result = from_json( Encode::decode( "utf8", $Response->content ) );
     
      #Если сервис не вернул подсказки, возвращаем undef
      if( defined( $Result ) && ( !exists( $Result->{predictions} ) || exists $Result->{error_message} ) )
      {
        $Result = undef;
      }
    }
    
    return $Result;
  }
  
  #Ищет среди возвращённых сервисом подсказок целевую
  sub FindPrediction( $$$$$ )
  {
    my ( $self, $Test, $Suggestions, $Stage, $LimitTopN ) = @_;
    
    my $Result = "";
    
    foreach my $Value ( @{ $Suggestions->{predictions} } )
    {
      #Сравниваем подсказку с целевым результатом, если совпала, значит сервис сделал правильное предсказание
      if( $self->CompareTestWithSuggestion( $Test, $Value->{terms}, $Stage ) == 1 )
      {
        $Result = $Value->{description};
        last;
      }
      $LimitTopN --;
      last if( $LimitTopN == 0 );
    }
    
    return $Result;
  }
  
  #Сравнивает полученную от сервиса подсказку с целевым значением
  sub CompareTestWithSuggestion( $$$ )
  {
    my ( $self, $Test, $Terms, $Stage ) = @_;
    
    my $RetVal = 0;
    
    #Дробим на подстроки значение, которое вернул Google
    my @SubValues = map( { $_->{value} } @$Terms );
    
    #Строки должны идти в следующем порядке: ул. Андрухаева, Адыгейск, Республика Адыгея, Россия
    #Другие примеры: 
    #улица Асаткина, Владимир, Владимирская область, Россия
    #Орёл, Орловская область, Россия
    #Москва, город Москва, Россия
    if( scalar( @SubValues ) > 1 && $SubValues[ scalar( @SubValues ) - 1 ] eq "Россия" )
    {
      #Перебираем все варианты
      if( $Stage eq "city" )
      {
        #Город, Регион, Россия 
        if( scalar( @SubValues ) == 3 )
        {
          $RetVal = ( $self->CompareRegion( $Test, $SubValues[1] ) && 
                      $self->CompareCity( $Test, $SubValues[0] ) ? 1 : 0 );
        }
      }
      elsif( $Stage eq "street" )
      {
        #Улица, Город, Регион, Россия
        if( scalar( @SubValues ) == 4 )
        {
          $RetVal = ( $self->CompareRegion( $Test, $SubValues[2] ) && 
                      $self->CompareCity( $Test, $SubValues[1] ) &&
                      $self->CompareStreet( $Test, $SubValues[0] ) ? 1 : 0 );
        }
      }
    }
    
    return $RetVal;
  }
  
  #Заменяет в строке буквы Ё на Е, ё на е 
  sub DegradeAlpha( $ )
  {
    my ( $self, $Strings ) = @_;
    
    $Strings =~ s/Ё/Е/gs;
    $Strings =~ s/ё/е/gs;
    
    return $Strings;
  }

  #Удаляет из строки $Value заданные подстроки. Строка $Value передаётся по ссылке
  sub DeleteStrings( $$$ )
  {
    my ( $self, $Value, $Strings ) = @_;
    
    my $Found = 0;
    
    #удаляем буквы ё из сравниваемых строк
    $$Value = $self->DegradeAlpha( $$Value );
    
    #Удаляем все альтернативные названия 
    foreach my $String ( @$Strings )
    {
      $String = $self->DegradeAlpha( $String );
      $Found = 1 if( $$Value =~ s/\b\Q$String\E\b//gi );
    }
    
    return $Found;
  }
  
  #Удляет все слова второй строки из первой строки. Первая строка передаётся по ссылке
  sub DeleteByWords( $$$ )
  {
    my ( $self, $String1, $String2 ) = @_;
    
    #получам слова тестового названия
    my @Words = grep { length( $_ ) > 0 } split /\W/, $String2;
    
    #сортируем по убыванию их длин
    @Words = sort { length($b) <=> length($a) } @Words;
    
    return $self->DeleteStrings( $String1, \@Words );
  }
  
  #Преобразует имена некторых регионов из тестов в имена, принятые в данном сервисе
  sub TransformRegionName( $$ )
  {
    my ( $self, $RegName ) = @_;
    
    if( $RegName eq "Тыва" )
    {
      $RegName = "Тува";
    }
    elsif( $RegName eq "Удмуртская" )
    {
      $RegName = "Удмуртия"
    }
    
    return $RegName;
  }
  
  #Сравнивает регион, полученный от сервиса с регионом целевого адреса
  sub CompareRegion( $$$ )
  {
    my ( $self, $Test, $Value ) = @_;
    
    my $TestValue = $self->TransformRegionName( $Test->{reg} );
    my $TestType = $Test->{reg_type};
    
    #Удаляем все альтернативные названия типа
    $self->DeleteStrings( \$Value, $RegionTypes{ $TestType } );
    
    #Удаляем все слова целевого названия из полученной подсказки
    my $Found = $self->DeleteByWords( \$Value, $TestValue );
    
    #Удаляем слова самого типа
    $self->DeleteByWords( \$Value, $TestType );
    
    #Удаляем знаки пунктуации и пробелы
    my @Words = grep { length( $_ ) > 0 } split /\W/, $Value;
  
    return ( $Found == 1 && scalar( @Words ) == 0 ? 1 : 0 );
  }
  
  #Сравнивает город, полученный от сервиса с городом целевого адреса
  sub CompareCity( $$$ )
  {
    my ( $self, $Test, $Value ) = @_;
    
    #Учитываем вариант, когда в тесте задан город-регион
    my $TestValue = $Test->{city};
    $TestValue = $Test->{reg} if( $TestValue eq "" );
    
    my $TestType = $Test->{city_type};
    $TestType = $Test->{reg_type} if( $TestType eq "" );
    
    #Удаляем все альтернативные названия типа
    $self->DeleteStrings( \$Value, $CityTypes{ $TestType } );
    
    #Удаляем все слова целевого названия из полученной подсказки
    my $Found = $self->DeleteByWords( \$Value, $TestValue );
    
    #Удаляем слова самого типа
    $self->DeleteByWords( \$Value, $TestType );
    
    #Удаляем знаки пунктуации и пробелы
    my @Words = grep { length( $_ ) > 0 } split /\W/, $Value;
  
    return ( $Found == 1 && scalar( @Words ) == 0 ? 1 : 0 );
  }
  
  #Сравнивает улицу, полученную от сервиса с улицей целевого адреса
  sub CompareStreet( $$$ )
  {
    my ( $self, $Test, $Value ) = @_;
    
    my $TestValue = $Test->{street};
    my $TestType = $Test->{street_type};
    
    #Удаляем все альтернативные названия типа
    $self->DeleteStrings( \$Value, $StreetTypes{ $TestType } );
    
    #Удаляем все слова целевого названия из полученной подсказки
    my $Found = $self->DeleteByWords( \$Value, $TestValue );
    
    #Удаляем слова самого типа
    $self->DeleteByWords( \$Value, $TestType );
    
    #Удаляем знаки пунктуации и пробелы
    my @Words = grep { length( $_ ) > 0 } split /\W/, $Value;
  
    return ( $Found == 1 && scalar( @Words ) == 0 ? 1 : 0 );
  }
}
1;