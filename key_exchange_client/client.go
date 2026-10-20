package key_exchange_client

import (
	"context"
	"fmt"
	"time"

	pb "github.com/ironcore-dev/metalbond/key_exchange_client/proto"
	"github.com/sirupsen/logrus"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

type KeyExchangeClient struct {
	client pb.AgentServiceClient
	conn   *grpc.ClientConn
	isInit bool
}

func NewKeyExchangeClient(targetURL string) (*KeyExchangeClient, error) {
	conn, err := grpc.NewClient(targetURL, grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		return nil, fmt.Errorf("failed to connect to agent at %s: %v", targetURL, err)
	}

	return &KeyExchangeClient{
		client: pb.NewAgentServiceClient(conn),
		conn:   conn,
		isInit: true,
	}, nil
}

func (kec *KeyExchangeClient) Init(ctx context.Context, clientName, clientPrefix string) error {
	_, err := kec.client.Init(ctx, &pb.AgentInitReq{
		ClientName:   clientName,
		ClientPrefix: clientPrefix,
	})
	return err
}

func (kec *KeyExchangeClient) Subscribe(ctx context.Context, vni uint32) error {
	if kec.isInit == false {
		logrus.Error("Network encryption was requested, but key-exchange was not configured.")
		return nil
	}
	_, err := kec.client.Subscribe(ctx, &pb.AgentSubscribeReq{Vni: vni})
	return err
}

func (kec *KeyExchangeClient) Unsubscribe(ctx context.Context, vni uint32) error {
	if kec.isInit == false {
		return nil
	}
	_, err := kec.client.Unsubscribe(ctx, &pb.AgentUnsubscribeReq{Vni: vni})
	return err
}

func (kec *KeyExchangeClient) IsKeyReady(ctx context.Context, vni, timeout uint32) (bool, error) {
	if kec.isInit == false {
		return true, nil
	}
	for range timeout {
		isReadyRes, err := kec.client.IsKeyReady(ctx, &pb.AgentKeyReadyReq{Vni: vni})
		if err != nil {
			return false, err
		}

		if isReadyRes.IsReady {
			return true, nil
		}

		time.Sleep(1 * time.Second)
	}

	return false, fmt.Errorf("Timeout while requesting key")
}

func (kec *KeyExchangeClient) Close() {
	if kec.isInit == false {
		return
	}
	if kec.conn != nil {
		kec.conn.Close()
	}
}
