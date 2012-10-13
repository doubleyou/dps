
Записки по разработке
====================


Синхронная репликация каждого сообщения оказалась ужасно медленной.
Пришлось выносить её в отдельный процесс, который ждет по 50 мс и отсылает сообщения пачкой.



На бенчмарке (1000 клиентов, 1-2 канала подписки, шлют сообщения 1 RPS, очередь глубиной 100) всплыло:
на одном сервере CPU 20-140% на Amazon Large Instance.
При включении репликации всё отваливается по таймауту.


Вставили в publish проверку: при таймауте на публикацию в канал проверяем очередь сообщений.
После вставки этой отладки выяснилось, что канал блокируется при длине очереди сообщений чуть более 150.
Из них:
65 unsubscribe
67 subscribe
23 publish

Делаем вывод, что канал занимается только тем, что подписывает и отписывает временных клиентов.


!! Надо указывать внутри модуля не messages_limit(), а ?MODULE:messages_limit(), что бы можно было meck-ать.



Зафискированные проблемы (без понимания их фатальности)

1. Пришедший long-poll клиент шлет 2*N сообщений на subscribe/unsubscribe. Как следствие,
одно пришедшее ему сообщение порождает целую кучу остальных
2. Тест на посылку 2000 сообщений проваливается когда длина очереди 1000, но проходит когда 100
Залипание происходит при пустой очереди сообщений у канала, таймаута в 500 мс не хватает на отработку
publish. Коммит 562a06e9a9e


Как выяснилось, тест не проходил из-за meck. Как только для теста был выключен meck, тормоза пропали.


Бенчмарки:

1. Модель поведения паблишеров и сабскрайберов приближена к множеству
пользователей чата или comet-сервера для информационных каналов вроде Facebook.

2. Каждый пользователь подписан на один или несколько случайных каналов, из
которых он вытаскивает сообщения

3. В эти же каналы он периодически асинхронно публикует сообщения (раз в секунду или реже).

4. bench.erl автоматически балансирует запросы между указанными серверами,
выполняя, таким образом, симуляцию load balancer'а.

5. Настройки для одного large instance: [{clients, 1000}, {channels, 10}, {channelns_per_client, {1, 2}}, {pub_interval, 1000}]



Бенчмарк меряет каждую секунду сколько было записано сообщений и прочитано. На коммит f3ac3114a состояние такое:

(node2@squeeze64)2> bench:start().
ok
0 publish/msec, 0 receive/msec
1140 publish/msec, 4373 receive/msec
1140 publish/msec, 0 receive/msec
1140 publish/msec, 0 receive/msec
1477 publish/msec, 0 receive/msec
1477 publish/msec, 0 receive/msec
1477 publish/msec, 0 receive/msec
1468 publish/msec, 0 receive/msec


Т.е. видимо что-то залипает и перестает публиковаться.



Дальше переписана и push-часть бенчмарка на cowboy_client. Результаты ещё более обескураживающие:

(node2@squeeze64)1> bench:start().
ok
521 publish, 8135 receive
327 publish, 21364 receive
** exception error: {invalid_push_response,500,

Т.е. это означает, что за 10 секунд на 800 паблишей породилось 30 000 рассылок и эта ситуация заблокировала каналы, потому что
в консоли веб-сервера пишется такое:

src/dps_channel.erl:67:<0.3291.0>: Error timeout in publish to channel_10007:
[{current_function,{dps_channel,'-distribute_message/3-lc$^0/1-0-',3}},
 {initial_call,{proc_lib,init_p,5}},
 {status,runnable},
 {message_queue_len,113},
 {messages,[{'$gen_call',{<0.2800.0>,#Ref<0.0.0.22845>},
                         {publish,<<"y u no love node.js?">>,
                                  1350151002349255}},
            {'$gen_call',{<0.3782.0>,#Ref<0.0.0.22879>},
                         {unsubscribe,<0.3782.0>}},
            {'$gen_call',{<0.2315.0>,#Ref<0.0.0.22880>},
                         {unsubscribe,<0.2315.0>}},
            {'$gen_call',{<0.2314.0>,#Ref<0.0.0.22881>},
                         {unsubscribe,<0.2314.0>}},
            {'$gen_call',{<0.2637.0>,#Ref<0.0.0.22892>},
                         {unsubscribe,<0.2637.0>}},




Дальше было решено проверить, сколько времени занимает unsubscribe. Время варьируется от 2 мкс до 3000 (!)

src/dps_channel.erl:181:<0.5012.0>: unsubscribe took 12
src/dps_channel.erl:181:<0.4997.0>: unsubscribe took 3075
src/dps_channel.erl:181:<0.4411.0>: unsubscribe took 10
src/dps_channel.erl:181:<0.4823.0>: unsubscribe took 22
src/dps_channel.erl:181:<0.5006.0>: unsubscribe took 72
src/dps_channel.erl:181:<0.5009.0>: unsubscribe took 108
src/dps_channel.erl:181:<0.5003.0>: unsubscribe took 25
src/dps_channel.erl:181:<0.4994.0>: unsubscribe took 16






Было принято решение сделать механизм под названием subscribe_once и unsubscribe_once, который позволял бы
автоматически отписывать потребителя от канала после получения первой пачки сообщений.

Результат проработал дольше (коммит 5782336):

(node2@squeeze64)1> bench:start().
ok
279 publish, 12612 receive
279 publish, 9186 receive
279 publish, 4811 receive
711 publish, 54734 receive
711 publish, 38409 receive
550 publish, 43456 receive
575 publish, 45967 receive
633 publish, 45217 receive
604 publish, 41727 receive
740 publish, 35102 receive
732 publish, 116532 receive
523 publish, 49317 receive




Однако подход с subscribe_once особо не решил проблему, поэтому было принято решение померять  суммарное время,
которое dps_channel проводит в обработке тех или иных вызовов. Коммит 126b40f

Получилась такая картина:
Chan channel_10006: publish 70/334012, subscribe 277/4238, unsubscribe: 277/35945
Chan channel_10002: publish 70/521355, subscribe 325/44876, unsubscribe: 325/76663
Chan channel_10003: publish 60/235228, subscribe 267/1871, unsubscribe: 267/32978
Chan channel_10004: publish 64/227141, subscribe 297/3573, unsubscribe: 297/66013


Т.е. рассылка сообщений происходит в 4-5 раз реже чем подписка, но занимает в 10-100 раз больше времени.

Следовательно имеет смысл оптимизировать рассылку сообщений.






