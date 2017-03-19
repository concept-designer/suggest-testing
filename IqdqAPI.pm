#Обёртка для работы с API сервиса iqdq.ru
package IqdqAPI;
{
  use strict;
  use warnings;
  use utf8;
  use LWP::UserAgent;
  use HTTP::Request;
  use HTTP::Request::Common;
  use JSON;
  use Encode;
  
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
    
    my $Request = POST( "http://iqdq.ru/services/IQDQ/SelectAddress?country=RU&LETTERS=$Prefix&",
                        'Content-Type' => 'application/x-www-form-urlencoded',
                        'Accept' => '*/*',
                        'Origin' => 'http://iqdq.ru',
                        'Host' => 'iqdq.ru',
                        'Referer' => 'http://iqdq.ru/ru-RU/testservices' );
                        
    my $Response = $self->{ user_agent }->request( $Request );
    
    my $Result = undef;
    
    if( defined($Response) && $Response->is_success() )
    {
      $Result = from_json( Encode::decode( "utf8", $Response->content ) );

      $Result = undef if( defined $Result && ref($Result) ne 'ARRAY' );
    }
    
    return $Result;
  }
  
  #Возвращает массив префиксов для названия города
  # Метод добавлен чисто для проверки, как себя будет вести данный сервис, если добавить тип города
  # - Test - исходный тест, откуда берёт название города
  sub BuildCityPrefixes_JustForTest( $$ )
  {
    my ( $self, $Test ) = @_;
    
    my $Result = [];
      
    my $TestName = $Test->{city};
    $TestName = $Test->{reg} if( $TestName eq "" && $Test->{reg_type} eq "г" );
    
    my $TestType = $Test->{city_type};
    $TestType = $Test->{reg_type} if( $TestType eq "" && $Test->{reg_type} eq "г" );
  
    my $Prefix = "";
    
    #сначала подставляем тип города, без него данный сервис города подсказывает плохо
    foreach my $Letter ( split( "", $TestType ) )
    {
      $Prefix .= $Letter;
      push @$Result, $Prefix;
    }
    
    $Prefix .= " ";
    
    #теперь подставляем буквы самого города
    foreach my $Letter ( split( "", $TestName ) )
    {
      $Prefix .= $Letter;
      push @$Result, $Prefix;
    }
    
    #Добавляем пробел к последнему префиксу, чтобы сообщить, что это полное имя города
    push @$Result, $Prefix." ";
    
    return $Result;
  }
  
  #Ищет среди возвращённых сервисом подсказок целевую
  sub FindPrediction( $$$$$ )
  {
    my ( $self, $Test, $Suggestions, $Stage, $LimitTopN ) = @_;
    
    my $Result = "";
    
    foreach my $Value ( @$Suggestions )
    {
      #Сравниваем подсказку с целевым результатом, если совпала, значит сервис сделал правильное предсказание
      if( $self->CompareTestWithSuggestion( $Test, $Value, $Stage ) == 1 )
      {
        $Result = $Value->{c_fullname};
        last;
      }
      $LimitTopN --;
      last if( $LimitTopN == 0 );
    }
    
    return $Result;
  }
  
  #Сравнивает полученную от сервиса подсказку с целевым значением
  #Данный сервис возвращает коды КЛАДР, поэтому реально сравниваем целевой код с полученным
  sub CompareTestWithSuggestion( $$$ )
  {
    my ( $self, $Test, $Value, $Stage ) = @_;
    
    my $RetVal = 0;
    
    my $KLADR_ID = $Value->{c_k5};
    
    #Добавляем к коду лидирующий ноль, т.к. сервис его отрезал
    if( length($KLADR_ID) == 16 )
    {
      $KLADR_ID = "0".$KLADR_ID;
    }
    
    if( $Stage eq "city" )
    {
      if( $Test->{city_kladr} ne "" )
      {
        #Если код КЛАДР содержит информацию о доме, отрезаем её
        $KLADR_ID = substr( $KLADR_ID, 0, length( $Test->{city_kladr} ) ) if( length( $KLADR_ID  ) > length( $Test->{city_kladr} ) );
        
        $RetVal = ( $Test->{city_kladr} eq $KLADR_ID ? 1 : 0 );
      }
      else
      {
        #Если код КЛАДР содержит информацию о доме, отрезаем её
        $KLADR_ID = substr( $KLADR_ID, 0, length( $Test->{reg_kladr} ) ) if( length( $KLADR_ID  ) > length( $Test->{reg_kladr} ) );
        
        $RetVal = ( $Test->{reg_kladr} eq $KLADR_ID ? 1 : 0 );
      }
    }
    elsif( $Stage eq "street" )
    {
      #Если код КЛАДР содержит информацию о доме, отрезаем её
      if( length( $KLADR_ID  ) > length( $Test->{street_kladr} ) )
      {
        $KLADR_ID = substr( $KLADR_ID, 0, length( $Test->{street_kladr} ) );
      }
      
      $RetVal = ( $Test->{street_kladr} eq $KLADR_ID ? 1 : 0 );
    }
    
    #Если по коду КЛАДР сравнение не прошло, то сравниваем строками
    #Некоторые коды КЛАДР данный сервис возвращает неправильно
    if( $RetVal == 0 && $Value->{c_NPName} eq "" && $Value->{c_SubRegionName} eq "" )
    {
      if( $self->CompareValues( $Value->{c_RegionName}, $self->TransformRegionName( $Test->{reg} ) ) &&
          $self->CompareValues( $Value->{c_RegionType}, $Test->{reg_type} ) &&
          $self->CompareValues( $Value->{c_CityName}, $Test->{city} ) &&
          $self->CompareValues( $Value->{c_CityType}, $Test->{city_type} ) )
      {
        if( $Stage eq "street" )
        {
          if( $self->CompareValues( $Value->{c_StreetName}, $Test->{street} ) &&
              $self->CompareValues( $Value->{c_StreetType}, $Test->{street_type} ) )
          {
            $RetVal = 1;
          }
        }
        else
        {
          $RetVal = 1;
        }
      }
    }
    
    return $RetVal;
  }
  
  #Преобразует имена некторых регионов для корректного сравнения
  sub TransformRegionName( $$ )
  {
    my ( $self, $RegName ) = @_;
    
    if( $RegName eq "Чувашская" )
    {
      $RegName = "Чувашская-Чувашия";
    }
    
    return $RegName;
  }
  
  #Заменяет в строке буквы Ё на Е, ё на е 
  sub DegradeAlpha( $ )
  {
    my ( $self, $Strings ) = @_;
    
    $Strings =~ s/Ё/Е/gs;
    $Strings =~ s/ё/е/gs;
    
    return $Strings;
  }
  
  #Пословно сравнивает две строки
  sub CompareValues( $$$ )
  {
    my ( $self, $Val1, $Val2 ) = @_;
    
    my $Result = 1;
    
    #Удаляем знаки пунктуации и пробелы
    my @Words1 = grep { length( $_ ) > 0 } split /\W/, $self->DegradeAlpha( $Val1 );
    
    #Удаляем знаки пунктуации и пробелы
    my @Words2 = grep { length( $_ ) > 0 } split /\W/, $self->DegradeAlpha( $Val2 );
    
    if( scalar @Words1 == scalar @Words2 )
    {
      for( my $i = 0; $i < scalar @Words1; $i ++ )
      {
        if( $Words1[$i] ne $Words2[$i] )
        {
          $Result = 0;
          last;
        }
      }
    }
    else
    {
      $Result = 0;
    }
    
    return $Result;
  }
};
1;