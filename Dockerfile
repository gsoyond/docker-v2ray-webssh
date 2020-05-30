FROM python:3.7-slim
ENV TZ=Asia/Shanghai 
RUN pip install webssh && \
    rm -rf /tmp/* /var/tmp/* /var/cache/apk/* 
EXPOSE 8888
ENTRYPOINT ["wssh", "--address=0.0.0.0", "--port=8888"]
